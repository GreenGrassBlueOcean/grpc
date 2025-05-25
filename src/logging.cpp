// logging.cpp
#include <Rcpp.h>
#include <iostream> // For std::endl if used in RGRPC_LOG, and std::ostringstream
#include <sstream>  // For std::ostringstream
#include "common.h"

// Default log level (e.g., INFO or WARN for production, DEBUG for development)
RGRPC_LOG_LEVEL rgrpc_global_log_level = RGRPC_LOG_LEVEL_INFO;

// [[Rcpp::export]]
void rgrpc_set_log_level(int level) {
  if (level >= RGRPC_LOG_LEVEL_NONE && level <= RGRPC_LOG_LEVEL_TRACE) {
    rgrpc_global_log_level = static_cast<RGRPC_LOG_LEVEL>(level);
    Rcpp::Rcout << "[gRPC Config] C++ log level set to " << level << std::endl;
  } else {
    // Correct way to issue an R warning from C++
    std::ostringstream warning_msg;
    warning_msg << "Invalid gRPC log level provided (" << level << "). Level unchanged.";
    Rcpp::warning(warning_msg.str());
    // Or simply:
    // Rcpp::warning("Invalid gRPC log level provided. Level unchanged.");
  }
}

// Optional: Function to get current level
// [[Rcpp::export]]
int rgrpc_get_log_level() {
  return static_cast<int>(rgrpc_global_log_level);
}
