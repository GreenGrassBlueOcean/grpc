// common.h
#ifndef RGRPC_H
#define RGRPC_H

// Define log levels
enum RGRPC_LOG_LEVEL {
  RGRPC_LOG_LEVEL_NONE = 0, // Or OFF
  RGRPC_LOG_LEVEL_ERROR = 1,
  RGRPC_LOG_LEVEL_WARN = 2,
  RGRPC_LOG_LEVEL_INFO = 3,
  RGRPC_LOG_LEVEL_DEBUG = 4,
  RGRPC_LOG_LEVEL_TRACE = 5 // Most verbose
};

extern RGRPC_LOG_LEVEL rgrpc_global_log_level;

// Macro to check current level before logging
#define RGRPC_LOG(level, msg)                                                                            \
if (rgrpc_global_log_level >= level) {                                                                   \
  /* Prepend level string if desired */                                                                  \
  /* For simplicity here, just like before: */                                                           \
  Rcpp::Rcout << "[gRPC " << #level << "] (" << __FILE__ << ":" << __LINE__ << ") " << msg << std::endl; \
}

// Convenience macros for each level
#define RGRPC_LOG_ERROR(msg) RGRPC_LOG(RGRPC_LOG_LEVEL_ERROR, msg)
#define RGRPC_LOG_WARN(msg)  RGRPC_LOG(RGRPC_LOG_LEVEL_WARN, msg)
#define RGRPC_LOG_INFO(msg)  RGRPC_LOG(RGRPC_LOG_LEVEL_INFO, msg)
#define RGRPC_LOG_DEBUG(msg) RGRPC_LOG(RGRPC_LOG_LEVEL_DEBUG, msg)
#define RGRPC_LOG_TRACE(msg) RGRPC_LOG(RGRPC_LOG_LEVEL_TRACE, msg)

#endif // RGRPC_H
