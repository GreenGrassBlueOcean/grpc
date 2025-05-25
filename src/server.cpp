// server.cpp (Robust C-core example, echoes request or sends fixed reply)
#include <Rcpp.h> // For Rcpp::List, CharacterVector, logging macros if used

#include "common.h"

#include <grpc/support/log.h>
#include <grpc/support/time.h>
#include <grpc/support/alloc.h>
#include <grpc/grpc.h>
#include <grpc/credentials.h>
#include <grpc/byte_buffer.h>
#include <grpc/byte_buffer_reader.h>
#include <grpc/slice.h>

#include <string>
#include <vector>
#include <thread> // For std::this_thread::sleep_for (optional, for interrupt check)
#include <iostream>

// Tags for different server events
#define TAG_REQUEST_NEW_CALL (void*)1
#define TAG_READ_CLIENT_REQUEST (void*)2
#define TAG_SEND_SERVER_RESPONSE (void*)3
#define TAG_SERVER_SHUTDOWN (void*)99

static char* slice_to_c_string_safe(grpc_slice slice) {
  if (GRPC_SLICE_IS_EMPTY(slice)) return nullptr;
  return grpc_slice_to_c_string(slice);
}


// src/server.cpp

// Helper function to call R hook functions
void call_r_hook(const Rcpp::List& hooks,
                 const std::string& hook_name,
                 const Rcpp::List& params_to_send) { // Renamed the third argument for clarity
  if (hooks.containsElementNamed(hook_name.c_str())) {
    try {
      Rcpp::Function hook_function = Rcpp::as<Rcpp::Function>(hooks[hook_name]);
      RGRPC_LOG_TRACE("Robust Server: Calling R hook: " << hook_name);

      // ALWAYS call the R function with the params_to_send list.
      // If params_to_send is an empty list, the R function receives an empty list.
      hook_function(params_to_send);

      RGRPC_LOG_TRACE("Robust Server: R hook " << hook_name << " finished.");
    } catch (Rcpp::exception& ex) {
      Rcpp::Rcerr << "[gRPC Server Warning] Exception in R hook '" << hook_name << "': " << ex.what() << std::endl;
      RGRPC_LOG_TRACE("Robust Server: Exception in R hook '" << hook_name << "': " << ex.what());
    } catch (std::exception& ex_std) {
      Rcpp::Rcerr << "[gRPC Server Warning] std::exception in R hook '" << hook_name << "': " << ex_std.what() << std::endl;
      RGRPC_LOG_TRACE("Robust Server: std::exception in R hook '" << hook_name << "': " << ex_std.what());
    }
    catch (...) {
      Rcpp::Rcerr << "[gRPC Server Warning] Unknown exception in R hook '" << hook_name << "'." << std::endl;
      RGRPC_LOG_TRACE("Robust Server: Unknown exception in R hook '" << hook_name << "'.");
    }
  } else {
    RGRPC_LOG_INFO("Robust Server: R hook " << hook_name << " not found.");
  }
}


// Helper to convert grpc_byte_buffer to Rcpp::RawVector
// (You might want to move this to be a static helper function if not already global)
static Rcpp::RawVector grpc_byte_buffer_to_rawvector(grpc_byte_buffer* buffer) {
  if (!buffer) return Rcpp::RawVector(0);
  grpc_byte_buffer_reader reader;
  grpc_byte_buffer_reader_init(&reader, buffer); // Initialize reader
  grpc_slice slice = grpc_byte_buffer_reader_readall(&reader);

  Rcpp::RawVector raw_vec(GRPC_SLICE_LENGTH(slice));
  if (GRPC_SLICE_LENGTH(slice) > 0) {
    memcpy(raw_vec.begin(), GRPC_SLICE_START_PTR(slice), GRPC_SLICE_LENGTH(slice));
  }

  grpc_slice_unref(slice);
  // grpc_byte_buffer_reader_destroy(&reader); // Not strictly needed for readall as per gRPC docs for this simple case
  return raw_vec;
}

// [[Rcpp::export]]
void robust_grpc_server_run( Rcpp::List r_service_handlers,      // NEW: Will be 'server_functions' from R
                             Rcpp::CharacterVector r_hoststring,
                             Rcpp::List r_hooks,                 // NEW
                             int r_server_duration_seconds       // Default was 30, can be 0 for indefinite
                             ) {

  RGRPC_LOG_INFO("Robust Server: Initializing gRPC core...");

  // --- ADD GRPC TRACERS ---
  // To enable all tracers:
  //grpc_tracer_set_enabled("all", 1);
  // Or more specific ones that might be relevant:
  // grpc_tracer_set_enabled("timer", 1);
  // grpc_tracer_set_enabled("timer_check", 1);
  // grpc_tracer_set_enabled("cq_timeout", 1);
  // grpc_tracer_set_enabled("server_channel", 1);
  // grpc_tracer_set_enabled("connectivity_state", 1);
  // gpr_set_log_verbosity(GPR_LOG_SEVERITY_DEBUG); // For gpr_log messages from C-core
  // --- END GRPC TRACERS ---

  grpc_init();

  // Define an empty list to reuse for hooks that don't have specific C++ params
  Rcpp::List empty_params = Rcpp::List::create();

  grpc_server* server = grpc_server_create(NULL, NULL);
  if (!server) {
    grpc_shutdown();
    Rcpp::stop("Robust Server: grpc_server_create failed.");
  }
  call_r_hook(r_hooks, "server_create", empty_params);

  grpc_completion_queue* cq = grpc_completion_queue_create_for_next(NULL);
  if (!cq) {
    grpc_server_destroy(server);
    grpc_shutdown();
    Rcpp::stop("Robust Server: grpc_completion_queue_create_for_next failed.");
  }
  call_r_hook(r_hooks, "queue_create", empty_params);

  grpc_server_register_completion_queue(server, cq, NULL);

  std::string host_str = Rcpp::as<std::string>(r_hoststring[0]);
  RGRPC_LOG_INFO("Robust Server: Binding to " << host_str);
  grpc_server_credentials* insecure_creds = grpc_insecure_server_credentials_create();
  int port = grpc_server_add_http2_port(server, host_str.c_str(), insecure_creds);
  Rcpp::List bind_params = Rcpp::List::create(Rcpp::Named("port") = port);
  call_r_hook(r_hooks, "bind", bind_params);
  grpc_server_credentials_release(insecure_creds);

  if (port == 0) {
    grpc_completion_queue_destroy(cq); // Destroy CQ before server if registration happened
    grpc_server_destroy(server);
    grpc_shutdown();
    Rcpp::stop("Robust Server: Failed to bind server to port " + host_str);
  }
  RGRPC_LOG_INFO("Robust Server: Started, listening on port " << port);
  grpc_server_start(server);
  call_r_hook(r_hooks, "server_start", empty_params);

  // --- Server Loop ---
  // State for handling one call at a time (simplified for this example)
  grpc_call* current_call = nullptr;
  grpc_call_details call_details;
  grpc_metadata_array request_metadata_recv;
  grpc_byte_buffer* client_request_payload_bb = nullptr;

  grpc_call_details_init(&call_details);
  grpc_metadata_array_init(&request_metadata_recv);

  bool done = false;

  // Initial request for a new call
  RGRPC_LOG_DEBUG("Robust Server: Requesting first call with tag " << TAG_REQUEST_NEW_CALL);
  grpc_call_error request_error = grpc_server_request_call(server, &current_call, &call_details, &request_metadata_recv, cq, cq, TAG_REQUEST_NEW_CALL);
  if (request_error != GRPC_CALL_OK) {
    RGRPC_LOG_INFO("Robust Server: Initial grpc_server_request_call failed! Error: " << request_error);
    // Consider stopping the server if this fails, as it can't accept calls.
    done = true;
  }


  gpr_timespec loop_deadline = gpr_time_add(gpr_now(GPR_CLOCK_REALTIME), gpr_time_from_seconds(r_server_duration_seconds, GPR_TIMESPAN));


  call_r_hook(r_hooks, "run", empty_params);
  while (!done) {
    try {
      Rcpp::checkUserInterrupt(); // Check for R interrupt periodically
    } catch (Rcpp::internal::InterruptedException& e) {
      RGRPC_LOG_INFO("Robust Server: R interrupt detected, initiating shutdown.");
      done = true; // Will break out and go to shutdown sequence
      continue;
    }

    if (gpr_time_cmp(gpr_now(GPR_CLOCK_REALTIME), loop_deadline) > 0 && r_server_duration_seconds > 0) {
      RGRPC_LOG_INFO("Robust Server: Server duration reached, initiating shutdown.");
      done = true;
      continue;
    }


    gpr_timespec cq_deadline = gpr_time_add(gpr_now(GPR_CLOCK_REALTIME), gpr_time_from_seconds(1, GPR_TIMESPAN)); // Try 1 second
    //gpr_timespec cq_deadline = gpr_time_add(gpr_now(GPR_CLOCK_REALTIME), gpr_time_from_millis(200, GPR_TIMESPAN)); // Short poll
    grpc_event event;
    memset(&event, 0, sizeof(event)); // Zero it out
    //gpr_timespec cq_deadline = gpr_time_add(gpr_now(GPR_CLOCK_REALTIME), gpr_time_from_millis(200, GPR_TIMESPAN));
    event = grpc_completion_queue_next(cq, cq_deadline, NULL);

    std::string event_type_str = "UNKNOWN_EVENT(" + std::to_string(event.type) + ")";
    if (event.type == GRPC_QUEUE_TIMEOUT) event_type_str = "GRPC_QUEUE_TIMEOUT(0)";
    else if (event.type == GRPC_OP_COMPLETE) event_type_str = "GRPC_OP_COMPLETE(1)";
    else if (event.type == GRPC_QUEUE_SHUTDOWN) event_type_str = "GRPC_QUEUE_SHUTDOWN(2)";

    RGRPC_LOG_TRACE("Robust Server: Event - Type: " << event_type_str << " Tag: " << event.tag << " Success: " << event.success);

    if (event.type == GRPC_QUEUE_TIMEOUT) {
      RGRPC_LOG_TRACE("Robust Server: CQ Timeout. Continuing loop."); // Add specific log
      continue;
    }


    RGRPC_LOG_TRACE("Robust Server: Event type: " << event.type << " Tag: " << event.tag << " Success: " << event.success);

    if (event.type == GRPC_QUEUE_TIMEOUT) {
      continue; // Loop to check interrupt or server duration
    }
    if (event.type == GRPC_QUEUE_SHUTDOWN) {
      RGRPC_LOG_TRACE("Robust Server: CQ shutdown event received. Exiting loop.");
      done = true;
      continue;
    }

    // --- Process completion event ---
    if (event.tag == TAG_REQUEST_NEW_CALL) {
      if (!event.success) {
        RGRPC_LOG_TRACE("Robust Server: New call request failed or server shutting down. Requesting next call.");
        // If server is not shutting down, re-request. If it is, this will eventually stop.
        grpc_call_error request_error = grpc_server_request_call(server, &current_call, &call_details, &request_metadata_recv, cq, cq, TAG_REQUEST_NEW_CALL);
        if (request_error != GRPC_CALL_OK) {
          RGRPC_LOG_INFO("Robust Server: New call request failed or server shutting down, ERROR: " << request_error);
          // Consider stopping the server if this fails, as it can't accept calls.
          done = true;
        }
        continue;
      }
      RGRPC_LOG_TRACE("Robust Server: New call accepted. Method: " << (slice_to_c_string_safe(call_details.method) ? slice_to_c_string_safe(call_details.method) : "N/A"));

      // current_call is now valid. Prepare to read client's message.
      grpc_op ops_read[2];
      memset(ops_read, 0, sizeof(ops_read));
      grpc_op* op_r_ptr = ops_read;

      // Op 1: Send initial metadata (can be empty)
      op_r_ptr->op = GRPC_OP_SEND_INITIAL_METADATA;
      op_r_ptr->data.send_initial_metadata.count = 0;
      op_r_ptr->flags = 0; op_r_ptr->reserved = NULL; op_r_ptr++;

      // Op 2: Receive client's message
      op_r_ptr->op = GRPC_OP_RECV_MESSAGE;
      op_r_ptr->data.recv_message.recv_message = &client_request_payload_bb;
      op_r_ptr->flags = 0; op_r_ptr->reserved = NULL; op_r_ptr++;

      RGRPC_LOG_TRACE("Robust Server: Starting batch to RECV_MESSAGE with tag " << TAG_READ_CLIENT_REQUEST);
      grpc_call_error error_read = grpc_call_start_batch(current_call, ops_read, (size_t)(op_r_ptr - ops_read), TAG_READ_CLIENT_REQUEST, NULL);
      if (error_read != GRPC_CALL_OK) {
        RGRPC_LOG_INFO("Robust Server: Failed to start batch for RECV_MESSAGE. Error: " << error_read);
        // Clean up this call attempt and request a new one
        grpc_call_details_destroy(&call_details); // Destroy old details
        grpc_metadata_array_destroy(&request_metadata_recv); // Destroy old metadata
        grpc_call_unref(current_call); // Unref the failed call
        current_call = nullptr;
        grpc_call_error request_error = grpc_server_request_call(server, &current_call, &call_details, &request_metadata_recv, cq, cq, TAG_REQUEST_NEW_CALL);
        if (request_error != GRPC_CALL_OK) {
          RGRPC_LOG_INFO("Robust Server: Failed to start batch for RECV_MESSAGE! Error: " << request_error);
          // Consider stopping the server if this fails, as it can't accept calls.
          done = true;
        }

      }
    } else if (event.tag == TAG_READ_CLIENT_REQUEST) {

      grpc_status_code status_to_send = GRPC_STATUS_INTERNAL;
      std::string status_details_cpp_str = "Unknown server error before R handler dispatch.";
      Rcpp::RawVector response_raw_from_r(0); // Placeholder for response from R
      //std::string reply_message_str = "Hello from Robust C-Core Server!";
      //grpc_status_code status_to_send = GRPC_STATUS_OK;
      //const char* status_details_str = "OK";

      if (!event.success) {
        RGRPC_LOG_DEBUG("Robust Server: RECV_MESSAGE batch failed (e.g., client cancelled). Sending error.");
        status_to_send = GRPC_STATUS_CANCELLED; // Or INTERNAL, depending on why
        status_details_cpp_str = "Failed to receive client message or client cancelled.";
        if (client_request_payload_bb) { // Should be NULL if RECV_MESSAGE part failed
          grpc_byte_buffer_destroy(client_request_payload_bb);
          client_request_payload_bb = nullptr;
        }
      } else {
        RGRPC_LOG_TRACE("Robust Server: RECV_MESSAGE batch success.");
        char* method_c_str = slice_to_c_string_safe(call_details.method);
        std::string method_path_str = method_c_str ? method_c_str : "";
        if (method_c_str) {
          RGRPC_LOG_TRACE("Robust Server: Dispatching method path: " << method_path_str);
          gpr_free(method_c_str);
        } else {
          RGRPC_LOG_INFO("Robust Server: Method path is empty in call_details!");
          // This should ideally not happen if a call was accepted.
        }
        if (!client_request_payload_bb) {
          RGRPC_LOG_INFO("Robust Server: RECV_MESSAGE op complete, but no payload buffer (client_request_payload_bb is NULL).");
          status_to_send = GRPC_STATUS_INVALID_ARGUMENT;
          status_details_cpp_str = "Client did not send a message payload as expected for unary call.";
        }  else if (r_service_handlers.containsElementNamed(method_path_str.c_str())) {
          Rcpp::Function r_handler_closure = Rcpp::as<Rcpp::Function>(r_service_handlers[method_path_str]);

          Rcpp::RawVector request_raw_from_bb = grpc_byte_buffer_to_rawvector(client_request_payload_bb);
          // The original client_request_payload_bb is consumed by grpc_byte_buffer_to_rawvector
          // if it's to be destroyed there, or we destroy it here.
          // Let's assume grpc_byte_buffer_to_rawvector doesn't destroy it.
          grpc_byte_buffer_destroy(client_request_payload_bb);
          client_request_payload_bb = nullptr;

          try {
            RGRPC_LOG_TRACE("Robust Server: Calling R handler closure for method: " << method_path_str);
            response_raw_from_r = r_handler_closure(request_raw_from_bb);
            status_to_send = GRPC_STATUS_OK;
            status_details_cpp_str = "OK";
            RGRPC_LOG_TRACE("Robust Server: R handler successful. Response length: " << response_raw_from_r.length());
          } catch (Rcpp::exception& ex) {
            Rcpp::Rcerr << "[gRPC Server Error] Rcpp::exception in R handler for " << method_path_str << ": " << ex.what() << std::endl;
            RGRPC_LOG_TRACE("Robust Server: Rcpp::exception in R handler for " << method_path_str << ": " << ex.what());
            status_to_send = GRPC_STATUS_INTERNAL;
            status_details_cpp_str = "Error in R handler: " + std::string(ex.what());
          } catch (std::exception& ex_std) {
            Rcpp::Rcerr << "[gRPC Server Error] std::exception in R handler for " << method_path_str << ": " << ex_std.what() << std::endl;
            RGRPC_LOG_TRACE("Robust Server: std::exception in R handler for " << method_path_str << ": " << ex_std.what());
            status_to_send = GRPC_STATUS_INTERNAL;
            status_details_cpp_str = "System error in R handler: " + std::string(ex_std.what());
          } catch (...) {
            Rcpp::Rcerr << "[gRPC Server Error] Unknown exception in R handler for " << method_path_str << "." << std::endl;
            RGRPC_LOG_TRACE("Robust Server: Unknown exception in R handler for " << method_path_str);
            status_to_send = GRPC_STATUS_INTERNAL;
            status_details_cpp_str = "Unknown error during R handler execution.";
          }


        } else { // Method not found in r_service_handlers
          RGRPC_LOG_TRACE("Robust Server: Method '" << method_path_str << "' not found in R handlers. Sending UNIMPLEMENTED.");
          status_to_send = GRPC_STATUS_UNIMPLEMENTED;
          status_details_cpp_str = "Method not implemented or not found: " + method_path_str;
          if (client_request_payload_bb) { // Should have been handled above if NULL
            grpc_byte_buffer_destroy(client_request_payload_bb);
            client_request_payload_bb = nullptr;
          }
        }
      }

      // Prepare and send response
      grpc_op ops_send[3]; // Max ops: RECV_CLOSE, SEND_MESSAGE, SEND_STATUS
      memset(ops_send, 0, sizeof(ops_send));
      grpc_op* op_s_ptr = ops_send;
      int was_cancelled_by_client = 0; // Store client cancellation status

      // Op 1: Receive close from client (good practice to ensure client finished)
      op_s_ptr->op = GRPC_OP_RECV_CLOSE_ON_SERVER;
      op_s_ptr->data.recv_close_on_server.cancelled = &was_cancelled_by_client;
      op_s_ptr->flags = 0; op_s_ptr->reserved = NULL; op_s_ptr++;

      grpc_byte_buffer* server_response_payload_bb = nullptr;
      grpc_slice response_slice = grpc_empty_slice();


      if (status_to_send == GRPC_STATUS_OK) {
        response_slice = grpc_slice_from_copied_buffer( // Use response_raw_from_r here
          reinterpret_cast<const char*>(RAW(response_raw_from_r)),
          response_raw_from_r.length()
        );

        server_response_payload_bb = grpc_raw_byte_buffer_create(&response_slice, 1);
        // grpc_slice_unref(response_slice); // server_response_payload_bb owns it

        op_s_ptr->op = GRPC_OP_SEND_MESSAGE;
        op_s_ptr->data.send_message.send_message = server_response_payload_bb;
        op_s_ptr->flags = 0; op_s_ptr->reserved = NULL; op_s_ptr++;
      }

      // Op 2 or 3: Send status
      grpc_slice status_details_slice = grpc_slice_from_copied_string(status_details_cpp_str.c_str());
      op_s_ptr->op = GRPC_OP_SEND_STATUS_FROM_SERVER;
      op_s_ptr->data.send_status_from_server.trailing_metadata_count = 0;
      op_s_ptr->data.send_status_from_server.status = status_to_send;
      op_s_ptr->data.send_status_from_server.status_details = &status_details_slice;
      op_s_ptr->flags = 0; op_s_ptr->reserved = NULL; op_s_ptr++;

      RGRPC_LOG_TRACE("Robust Server: Starting batch to SEND_RESPONSE/STATUS with tag " << TAG_SEND_SERVER_RESPONSE);
      grpc_call_error error_send = grpc_call_start_batch(current_call, ops_send, (size_t)(op_s_ptr - ops_send), TAG_SEND_SERVER_RESPONSE, NULL);

      // Unref slices used in batch *after* start_batch if they were copied.
      // If they were from_static_string, no unref. grpc_raw_byte_buffer_create takes ownership.
      if (!GRPC_SLICE_IS_EMPTY(response_slice)) grpc_slice_unref(response_slice);
      grpc_slice_unref(status_details_slice);


      if (error_send != GRPC_CALL_OK) {
        RGRPC_LOG_INFO("Robust Server: Failed to start batch for SEND_RESPONSE. Error: " << error_send);
        if (server_response_payload_bb) grpc_byte_buffer_destroy(server_response_payload_bb);
        // Fall through to cleanup for this call
      }
      // The completion of TAG_SEND_SERVER_RESPONSE will handle full cleanup for this call.

    } else if (event.tag == TAG_SEND_SERVER_RESPONSE) {
      RGRPC_LOG_TRACE("Robust Server: SEND_RESPONSE/STATUS batch complete. Success: " << event.success);
      // Full cleanup for this call
      grpc_call_details_destroy(&call_details); // Destroy old details
      grpc_metadata_array_destroy(&request_metadata_recv); // Destroy old metadata
      grpc_call_unref(current_call);
      current_call = nullptr;

      // Request the next call
      RGRPC_LOG_TRACE("Robust Server: Requesting next call with tag " << TAG_REQUEST_NEW_CALL);
      grpc_call_details_init(&call_details); // Re-init for next call
      grpc_metadata_array_init(&request_metadata_recv); // Re-init for next call
      grpc_call_error request_error = grpc_server_request_call(server, &current_call, &call_details, &request_metadata_recv, cq, cq, TAG_REQUEST_NEW_CALL);
      if (request_error != GRPC_CALL_OK) {
        RGRPC_LOG_INFO("Robust Server: Requesting next call with tag failed! Error: " << request_error);
        // Consider stopping the server if this fails, as it can't accept calls.
        done = true;
      }
    } else {
      RGRPC_LOG_INFO("Robust Server: Unknown or unhandled tag. Event Type: " << event.type
                                                                        << " Tag: " << event.tag << " Success: " << event.success);
      // If event.type is GRPC_OP_COMPLETE (1), what call object was it for?
      // This is hard to know without more context or if it's an internal event.
    }
  } // end while(!done)

  // --- Shutdown Sequence ---
  RGRPC_LOG_INFO("Robust Server: Shutting down server...");
  if (server && cq) { // cq might be null if init failed early
    call_r_hook(r_hooks, "shutdown",empty_params);
    grpc_server_shutdown_and_notify(server, cq, TAG_SERVER_SHUTDOWN);
    RGRPC_LOG_TRACE("Robust Server: Draining CQ for server shutdown event (tag " << TAG_SERVER_SHUTDOWN << ")");
    // Wait for the shutdown notification
    gpr_timespec shutdown_deadline = gpr_time_add(gpr_now(GPR_CLOCK_REALTIME), gpr_time_from_seconds(5, GPR_TIMESPAN));
    grpc_event shutdown_event;
    do {
      shutdown_event = grpc_completion_queue_next(cq, shutdown_deadline, NULL);
    } while (shutdown_event.type != GRPC_OP_COMPLETE && shutdown_event.tag != TAG_SERVER_SHUTDOWN && shutdown_event.type != GRPC_QUEUE_TIMEOUT && shutdown_event.type != GRPC_QUEUE_SHUTDOWN);

    if (shutdown_event.type == GRPC_OP_COMPLETE && shutdown_event.tag == TAG_SERVER_SHUTDOWN) {
      RGRPC_LOG_TRACE("Robust Server: Server shutdown notification received.");
    } else {
      RGRPC_LOG_INFO("Robust Server: Did not get clean server shutdown event. Type: " << shutdown_event.type);
    }
    // Cancel any pending calls that might have been accepted after shutdown was initiated
    // but before the TAG_REQUEST_NEW_CALL handler stopped re-requesting.
    grpc_server_cancel_all_calls(server);
  }

  if (current_call) { // If a call was active when server loop exited
    RGRPC_LOG_INFO("Robust Server: Cleaning up active call during shutdown.");
    // It's tricky to know the exact state. A simple unref might be best.
    // Or try to send a CANCELLED status if appropriate.
    // For simplicity here, just unref.
    grpc_call_unref(current_call);
    grpc_call_details_destroy(&call_details);
    grpc_metadata_array_destroy(&request_metadata_recv);
    if (client_request_payload_bb) grpc_byte_buffer_destroy(client_request_payload_bb);
  }


  if (server) {
    grpc_server_destroy(server);
    server = nullptr;
  } // Destroy server after CQ is fully handled for it
  if (cq) {
    grpc_completion_queue_shutdown(cq); // Ensure it's shutdown
    RGRPC_LOG_TRACE("Robust Server: Draining CQ completely before destruction...");
    while (grpc_completion_queue_next(cq, gpr_time_0(GPR_CLOCK_REALTIME), NULL).type != GRPC_QUEUE_SHUTDOWN);
    grpc_completion_queue_destroy(cq); cq = nullptr;
  }

  RGRPC_LOG_TRACE("Robust Server: Shutting down gRPC library...");
  grpc_shutdown();
  call_r_hook(r_hooks, "stopped",empty_params);
  RGRPC_LOG_INFO("Robust Server: [STOPPED]");
}
