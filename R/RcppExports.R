# Generated by using Rcpp::compileAttributes() -> do not edit by hand
# Generator token: 10BE3573-1514-4C36-9D1C-5A225CD40393

robust_grpc_client_call <- function(r_target_str, r_method_str, r_request_payload, r_metadata_sexp = NULL) {
    .Call(`_grpc_robust_grpc_client_call`, r_target_str, r_method_str, r_request_payload, r_metadata_sexp)
}

rgrpc_set_log_level <- function(level) {
    invisible(.Call(`_grpc_rgrpc_set_log_level`, level))
}

rgrpc_get_log_level <- function() {
    .Call(`_grpc_rgrpc_get_log_level`)
}

minimal_start_server_test <- function(address_str) {
    .Call(`_grpc_minimal_start_server_test`, address_str)
}

robust_grpc_server_run <- function(r_service_handlers, r_hoststring, r_hooks, r_server_duration_seconds) {
    invisible(.Call(`_grpc_robust_grpc_server_run`, r_service_handlers, r_hoststring, r_hooks, r_server_duration_seconds))
}

