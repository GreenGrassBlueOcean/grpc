// [[Rcpp::depends(Rcpp)]]
// [[Rcpp::plugins(cpp17)]]

#include <Rcpp.h>
#include <string>
#include <vector>
#include <chrono>
#include <thread>

// gRPC C API headers
#include <grpc/grpc.h>          // Main gRPC header
//#include <grpc/grpc_security.h> // For grpc_insecure_server_credentials_create etc.
#include <grpc/credentials.h> // For grpc_insecure_server_credentials_create

// No Rcpp namespace using for clarity with Rcpp::

// [[Rcpp::export]]
int minimal_start_server_test(std::string address_str) {
  Rcpp::Rcout << "Minimal server: Initializing gRPC..." << std::endl;
  grpc_init();

  Rcpp::Rcout << "Minimal server: Creating server..." << std::endl;
  grpc_server* server = grpc_server_create(NULL, NULL);
  if (!server) {
    Rcpp::Rcout << "Minimal server: ERROR - grpc_server_create failed." << std::endl;
    grpc_shutdown();
    return -1; // Error code for server creation failure
  }

  Rcpp::Rcout << "Minimal server: Creating insecure server credentials..." << std::endl;
  grpc_server_credentials* insecure_creds = grpc_insecure_server_credentials_create();
  if (!insecure_creds) {
    Rcpp::Rcout << "Minimal server: ERROR - grpc_insecure_server_credentials_create failed." << std::endl;
    grpc_server_destroy(server);
    grpc_shutdown();
    return -2; // Error code for credential creation failure
  }

  Rcpp::Rcout << "Minimal server: Adding insecure port using grpc_server_add_http2_port with GRPC_INSECURE_SERVER_CREDENTIALS: " << address_str << std::endl;

  // Use the generic add_http2_port function, passing the insecure_creds object
  int port = grpc_server_add_http2_port(server, address_str.c_str(), insecure_creds);

  grpc_server_credentials_release(insecure_creds); // Release credentials after adding port

  Rcpp::Rcout << "Minimal server: Port returned: " << port << std::endl;
  if (port == 0) {
    Rcpp::Rcout << "Minimal server: ERROR - Failed to add/bind port. gRPC C-core returned 0. Check console for gRPC core errors (e.g. 'No credentials specified for secure port' should NOT appear now)." << std::endl;
    grpc_server_destroy(server);
    grpc_shutdown();
    return -3; // Error code for port binding failure
  }

  Rcpp::Rcout << "Minimal server: Starting server..." << std::endl;
  grpc_server_start(server);
  Rcpp::Rcout << "Minimal server: Server reported as started on port " << port << "." << std::endl;
  Rcpp::Rcout << "Minimal server: If no gRPC core errors appeared above, try connecting a client." << std::endl;
  Rcpp::Rcout << "Minimal server: Test loop for 30 seconds (Press Esc in R console to interrupt)..." << std::endl;

  for(int i = 0; i < 30; ++i) {
    try {
      Rcpp::checkUserInterrupt();
    } catch (Rcpp::internal::InterruptedException& e) {
      Rcpp::Rcout << "Minimal server: Interrupt detected by Rcpp, initiating shutdown..." << std::endl;
      break;
    }
    std::this_thread::sleep_for(std::chrono::seconds(1));
    if (i % 5 == 4) {
      Rcpp::Rcout << "." << std::flush;
    }
  }
  Rcpp::Rcout << std::endl;

  Rcpp::Rcout << "Minimal server: Shutting down server..." << std::endl;
  grpc_completion_queue* cq_shutdown = grpc_completion_queue_create_for_pluck(NULL);
  if (!cq_shutdown) { // Should not happen if grpc_init was successful
    Rcpp::Rcout << "Minimal server: WARNING - Failed to create completion queue for shutdown notification." << std::endl;
  }

  grpc_server_shutdown_and_notify(server, cq_shutdown, NULL);

  gpr_timespec deadline = gpr_time_add(gpr_now(GPR_CLOCK_REALTIME), gpr_time_from_seconds(5, GPR_TIMESPAN));
  grpc_event shutdown_event = grpc_completion_queue_pluck(cq_shutdown, NULL, deadline, NULL);

  if (shutdown_event.type == GRPC_OP_COMPLETE && shutdown_event.success) {
    Rcpp::Rcout << "Minimal server: Shutdown notification received." << std::endl;
  } else if (shutdown_event.type == GRPC_QUEUE_TIMEOUT) {
    Rcpp::Rcout << "Minimal server: WARNING - Timeout waiting for server shutdown notification. Forcing cancel." << std::endl;
    grpc_server_cancel_all_calls(server);
  } else {
    Rcpp::Rcout << "Minimal server: WARNING - Shutdown notification event not successful or unexpected type: " << shutdown_event.type << std::endl;
  }

  grpc_server_destroy(server);
  if (cq_shutdown) {
    grpc_completion_queue_destroy(cq_shutdown);
  }

  Rcpp::Rcout << "Minimal server: Shutting down gRPC library..." << std::endl;
  grpc_shutdown();
  Rcpp::Rcout << "Minimal server: Done." << std::endl;

  return port;
}
