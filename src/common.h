#ifndef RGRPC_H
#define RGRPC_H

/* Uncomment the line below to enable detailed gRPC debug logging to the R console */
#define RGRPC_DEBUG

#ifdef RGRPC_DEBUG
// If RGRPC_DEBUG is enabled, include Rcpp.h for Rcpp::Rcout and iostream for std::endl
#ifndef RCPP_H_GEN_
#include <Rcpp.h> // This guard is typical for Rcpp.h inclusion
#endif
#include <iostream> // For std::endl
// Define the logging macro to print messages
#define RGRPC_LOG(msg) Rcpp::Rcout << "[gRPC Debug] (" << __FILE__ << ":" << __LINE__ << ") " << msg << std::endl
#else
// If RGRPC_DEBUG is not defined, the logging macro does nothing
#define RGRPC_LOG(msg)
#endif

// No need to define RESERVED as NULL; just use NULL directly in gRPC C API calls.

#endif // RGRPC_H
