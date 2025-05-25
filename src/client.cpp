/*
 * Based on the user's initial client.cpp with robustness improvements.
 */
#include <grpcpp/grpcpp.h> // For grpc::StatusCode names if desired for logging, not strictly needed for C-API
#include <grpc/support/log.h>
#include <grpc/support/time.h>
#include <grpc/grpc.h>
#include <grpc/credentials.h> // For grpc_insecure_credentials_create
#include <grpc/byte_buffer.h>
#include <grpc/byte_buffer_reader.h>

#include "common.h"

#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <Rcpp.h> // For Rcpp::RawVector, Rcpp::stop, etc.

static void* tag(intptr_t i) { return reinterpret_cast<void*>(i); }

static Rcpp::RawVector sliceToRawVector(grpc_slice slice) {
    size_t n = GRPC_SLICE_LENGTH(slice);
    Rcpp::RawVector out(n);
    if (n > 0) {
        memcpy(out.begin(), GRPC_SLICE_START_PTR(slice), n);
    }
    return out;
}

// [[Rcpp::export]]
Rcpp::RawVector robust_grpc_client_call( Rcpp::CharacterVector r_target_str,
                                         Rcpp::CharacterVector r_method_str,
                                         Rcpp::RawVector r_request_payload,
                                         SEXP r_metadata_sexp = R_NilValue) { // Optional metadata

  RGRPC_LOG_TRACE("Robust Client: Entered function."); // Your first log

  // --- ADD GRPC TRACERS & VERBOSITY ---
  // Best to set these before grpc_init()
  RGRPC_LOG_TRACE("Robust Client: Enabling gRPC C-core tracers (all) and debug verbosity.");
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

  Rcpp::List r_metadata; // Will hold the actual list
  if (r_metadata_sexp == R_NilValue) {
    r_metadata = Rcpp::List::create(); // C++ default if R passes nothing specific
  } else {
    // If R passes something (even an empty list()), convert it
    r_metadata = Rcpp::as<Rcpp::List>(r_metadata_sexp);
  }

  RGRPC_LOG_TRACE("Robust Client: Initializing gRPC core...");
  grpc_init(); // Should ideally be managed globally by the R package load/unload

  std::string target_str = Rcpp::as<std::string>(r_target_str[0]);
  std::string method_str = Rcpp::as<std::string>(r_method_str[0]);
  RGRPC_LOG_TRACE("Robust Client: Target: " << target_str << ", Method: " << method_str);

  grpc_channel* channel = nullptr;
  grpc_call* call = nullptr;
  grpc_completion_queue* cq = nullptr;
  grpc_byte_buffer* request_bb = nullptr;
  grpc_byte_buffer* response_bb = nullptr;
  Rcpp::RawVector result_rawvector;

  grpc_metadata_array initial_metadata_send;
  grpc_metadata_array_init(&initial_metadata_send); // For sending
  std::vector<grpc_metadata> metadata_store; // To keep metadata slices alive

  if (r_metadata.size() > 0 && r_metadata.size() % 2 == 0) {
    metadata_store.reserve(r_metadata.size() / 2);
    for (int i = 0; i < r_metadata.size(); i += 2) {
      std::string key_str = Rcpp::as<std::string>(r_metadata[i]);
      std::string val_str = Rcpp::as<std::string>(r_metadata[i+1]);

      grpc_metadata md; // Create the struct explicitly
      md.key = grpc_slice_from_copied_string(key_str.c_str());
      md.value = grpc_slice_from_copied_string(val_str.c_str());

      metadata_store.push_back(md); // Push back the constructed object
    }
    initial_metadata_send.count = metadata_store.size();
    initial_metadata_send.metadata = metadata_store.data();
  }


  grpc_metadata_array initial_metadata_recv;
  grpc_metadata_array_init(&initial_metadata_recv);
  grpc_metadata_array trailing_metadata_recv;
  grpc_metadata_array_init(&trailing_metadata_recv);
  grpc_slice details_slice_recv = grpc_empty_slice();
  grpc_status_code status_code_recv = GRPC_STATUS_UNKNOWN;

  cq = grpc_completion_queue_create_for_next(NULL);
  if (!cq) Rcpp::stop("Robust Client: Failed to create CQ.");

  RGRPC_LOG_TRACE("Robust Client: Creating insecure credentials...");
  grpc_channel_credentials* creds = grpc_insecure_credentials_create();
  if (!creds) {
    grpc_completion_queue_destroy(cq);
    grpc_shutdown();
    Rcpp::stop("Robust Client: grpc_insecure_credentials_create failed.");
  }

  grpc_channel_args channel_args = {0, NULL};
  RGRPC_LOG_TRACE("Robust Client: Creating channel using grpc_channel_create...");
  channel = grpc_channel_create(target_str.c_str(), creds, &channel_args);
  grpc_channel_credentials_release(creds); // Released once channel takes ownership or copies

  if (!channel) {
    grpc_completion_queue_destroy(cq);
    grpc_shutdown();
    Rcpp::stop("Robust Client: grpc_channel_create returned NULL.");
  }
  RGRPC_LOG_TRACE("Robust Client: Channel pointer: " << channel);

  gpr_timespec call_deadline = gpr_time_add(gpr_now(GPR_CLOCK_REALTIME), gpr_time_from_seconds(15, GPR_TIMESPAN));
  grpc_slice method_slice_grpc = grpc_slice_from_copied_string(method_str.c_str());

  RGRPC_LOG_TRACE("Robust Client: Creating call...");
  call = grpc_channel_create_call(channel, NULL, GRPC_PROPAGATE_DEFAULTS, cq,
                                  method_slice_grpc, NULL /* host_slice, can be target_str too */, call_deadline, NULL);
  grpc_slice_unref(method_slice_grpc); // Call has a ref now
  if (!call) {
    grpc_channel_destroy(channel);
    grpc_completion_queue_destroy(cq);
    grpc_shutdown();
    Rcpp::stop("Robust Client: grpc_channel_create_call returned NULL.");
  }
  RGRPC_LOG_TRACE("Robust Client: Call created: " << call);

  grpc_op ops[6];
  memset(ops, 0, sizeof(ops));
  grpc_op* op_ptr = ops;

  op_ptr->op = GRPC_OP_SEND_INITIAL_METADATA;
  op_ptr->data.send_initial_metadata.count = initial_metadata_send.count;
  op_ptr->data.send_initial_metadata.metadata = initial_metadata_send.metadata;
  op_ptr->flags = 0; op_ptr->reserved = NULL; op_ptr++;

  grpc_slice request_payload_slice_grpc = grpc_slice_from_copied_buffer(
    reinterpret_cast<const char*>(RAW(r_request_payload)), r_request_payload.length());
  request_bb = grpc_raw_byte_buffer_create(&request_payload_slice_grpc, 1);
  grpc_slice_unref(request_payload_slice_grpc); // request_bb has its own ref

  op_ptr->op = GRPC_OP_SEND_MESSAGE;
  op_ptr->data.send_message.send_message = request_bb;
  op_ptr->flags = 0; op_ptr->reserved = NULL; op_ptr++;

  op_ptr->op = GRPC_OP_SEND_CLOSE_FROM_CLIENT;
  op_ptr->flags = 0; op_ptr->reserved = NULL; op_ptr++;

  op_ptr->op = GRPC_OP_RECV_INITIAL_METADATA;
  op_ptr->data.recv_initial_metadata.recv_initial_metadata = &initial_metadata_recv;
  op_ptr->flags = 0; op_ptr->reserved = NULL; op_ptr++;

  op_ptr->op = GRPC_OP_RECV_MESSAGE;
  op_ptr->data.recv_message.recv_message = &response_bb;
  op_ptr->flags = 0; op_ptr->reserved = NULL; op_ptr++;

  op_ptr->op = GRPC_OP_RECV_STATUS_ON_CLIENT;
  op_ptr->data.recv_status_on_client.trailing_metadata = &trailing_metadata_recv;
  op_ptr->data.recv_status_on_client.status = &status_code_recv;
  op_ptr->data.recv_status_on_client.status_details = &details_slice_recv;
  op_ptr->flags = 0; op_ptr->reserved = NULL; op_ptr++;

  RGRPC_LOG_TRACE("Robust Client: Starting batch (" << (size_t)(op_ptr - ops) << " ops) with tag 1...");
  grpc_call_error error = grpc_call_start_batch(call, ops, (size_t)(op_ptr - ops), tag(1), NULL);

  std::string error_detail_str = "RPC failed.";
  if (error != GRPC_CALL_OK) {
    error_detail_str = "Robust Client: grpc_call_start_batch failed with error: " + std::to_string(error);
    RGRPC_LOG_INFO(error_detail_str);
    // Go to cleanup
  } else {
    RGRPC_LOG_TRACE("Robust Client: Waiting for batch completion (tag 1)...");
    grpc_event event = grpc_completion_queue_next(cq, call_deadline, NULL); // Use call_deadline or another appropriate one
    RGRPC_LOG_TRACE("Robust Client: Batch event: Type=" << event.type << " Tag=" << reinterpret_cast<intptr_t>(event.tag) << " Success=" << event.success);

    if (event.type == GRPC_OP_COMPLETE) {
      if (event.success) {
        RGRPC_LOG_TRACE("Robust Client: RPC batch successful. Status from server: " << status_code_recv);
        if (status_code_recv == GRPC_STATUS_OK) {
          if (response_bb) {
            grpc_byte_buffer_reader bbr;
            grpc_byte_buffer_reader_init(&bbr, response_bb);
            grpc_slice resp_slice = grpc_byte_buffer_reader_readall(&bbr);
            result_rawvector = sliceToRawVector(resp_slice);

            RGRPC_LOG_TRACE("Robust Client: Prepared result_rawvector. Length: " << result_rawvector.size());
            if (result_rawvector.size() > 0 && result_rawvector.size() < 50) { // Log a few bytes
              std::ostringstream oss;
              for (int k=0; k < result_rawvector.size() && k < 10; ++k) {
                oss << std::hex << static_cast<int>(result_rawvector[k]) << " ";
              }
              RGRPC_LOG_TRACE("Robust Client: result_rawvector (first 10 bytes hex): " << oss.str());
            }


            grpc_slice_unref(resp_slice);
            // grpc_byte_buffer_reader_destroy(&bbr); // Not needed for simple readall
          } else {
            RGRPC_LOG_TRACE("Robust Client: Status OK, but no response payload received.");
            // This can happen for server streaming responses where client closes early,
            // or if server sends OK but no message (valid for some RPCs).
          }
        } else { // Server returned non-OK status
          char* ds = grpc_slice_to_c_string(details_slice_recv);
          error_detail_str = "RPC failed with server status " + std::to_string(status_code_recv) + ": " + ds;
          gpr_free(ds);
          RGRPC_LOG_INFO(error_detail_str);
        }
      } else { // event.success == 0, batch failed (e.g., network error, server crash, client cancellation)
        error_detail_str = "RPC batch failed (event.success=0). Final status from server (if any): " + std::to_string(status_code_recv);
        if (GRPC_SLICE_LENGTH(details_slice_recv) > 0) {
          char* ds = grpc_slice_to_c_string(details_slice_recv);
          error_detail_str += ". Details: " + std::string(ds);
          gpr_free(ds);
        }
        RGRPC_LOG_INFO(error_detail_str);
        // status_code_recv might contain more info, e.g. GRPC_STATUS_CANCELLED
      }
    } else if (event.type == GRPC_QUEUE_TIMEOUT) {
      error_detail_str = "Robust Client: Call timed out waiting for completion queue.";
      RGRPC_LOG_INFO(error_detail_str);
      grpc_call_cancel_with_status(call, GRPC_STATUS_CANCELLED, "Client cancelled due to timeout", NULL);
    } else { // GRPC_QUEUE_SHUTDOWN or other unexpected event
      error_detail_str = "Robust Client: Unexpected event type from CQ: " + std::to_string(event.type);
      RGRPC_LOG_INFO(error_detail_str);
    }
  }

  RGRPC_LOG_TRACE("Robust Client: Cleaning up...");
  if (request_bb) {
    grpc_byte_buffer_destroy(request_bb);
    request_bb = nullptr;
  }
  if (response_bb) {
    grpc_byte_buffer_destroy(response_bb);
    response_bb = nullptr;
  }
  grpc_slice_unref(details_slice_recv);

  // Unref metadata slices from metadata_store if it was populated
  RGRPC_LOG_TRACE("Robust Client: Unreffing metadata_store slices (if any)...");
  for (const auto& meta : metadata_store) {
    // These slices were created with grpc_slice_from_copied_string
    grpc_slice_unref(meta.key);
    grpc_slice_unref(meta.value);
  }
  RGRPC_LOG_TRACE("Robust Client: metadata_store slices unreffed.");

  // THE FIX: Reset initial_metadata_send before destroying its struct
  RGRPC_LOG_TRACE("Robust Client: Resetting initial_metadata_send before destroy.");
  initial_metadata_send.metadata = nullptr;
  initial_metadata_send.count = 0;
  initial_metadata_send.capacity = 0;

  RGRPC_LOG_TRACE("Robust Client: Destroying initial_metadata_send array struct...");
  grpc_metadata_array_destroy(&initial_metadata_send);
  RGRPC_LOG_TRACE("Robust Client: initial_metadata_send array struct destroyed.");

  RGRPC_LOG_TRACE("Robust Client: Destroying initial_metadata_recv array...");
  grpc_metadata_array_destroy(&initial_metadata_recv);
  RGRPC_LOG_TRACE("Robust Client: initial_metadata_recv array destroyed.");

  RGRPC_LOG_TRACE("Robust Client: Destroying trailing_metadata_recv array...");
  grpc_metadata_array_destroy(&trailing_metadata_recv);
  RGRPC_LOG_TRACE("Robust Client: trailing_metadata_recv array destroyed.");

  RGRPC_LOG_TRACE("Robust Client: Unreffing call...");
  if (call) {
    grpc_call_unref(call);
    call = nullptr;
  }
  RGRPC_LOG_TRACE("Robust Client: Destroying channel...");
  if (channel) {
    grpc_channel_destroy(channel);
    channel = nullptr;
  }

  RGRPC_LOG_TRACE("Robust Client: Cleaning up CQ...");
  if (cq) {
    grpc_completion_queue_shutdown(cq);
    while (grpc_completion_queue_next(cq, gpr_time_0(GPR_CLOCK_REALTIME), NULL).type != GRPC_QUEUE_SHUTDOWN);
    grpc_completion_queue_destroy(cq);
    cq = nullptr;
  }
  RGRPC_LOG_TRACE("Robust Client: CQ cleaned up.");

  RGRPC_LOG_TRACE("Robust Client: Calling grpc_shutdown().");
  grpc_shutdown();
  RGRPC_LOG_INFO("Robust Client: Fetch function complete.");

  if (status_code_recv != GRPC_STATUS_OK) { // Removed result_rawvector.length() check for now, Rcpp::stop handles empty
    Rcpp::stop(error_detail_str); // error_detail_str should be populated if not OK
  }
  return result_rawvector; // RETURN THE ACTUAL RESULT
}
