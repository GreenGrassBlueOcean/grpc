#' Health Check Client Demo
#'
#' This demo shows how to connect to a gRPC server (expected to be
#' running the health check server demo), perform a health check,
#' and make a simple RPC call (SayHello).
#' Note: Requires the 'health-check-server' demo to be running
#' and its port written to 'health-check-server.port' in the R temp directory.
#' @demo health-check-client
#' @importFrom futile.logger flog.info flog.error flog.warn flog.threshold
#' @importFrom RProtoBuf P new readProtoFiles # readProtoFiles only if needed by read_services explicitly here

# --- Setup ---
library(grpc)
library(RProtoBuf)
library(futile.logger)

flog.threshold(futile.logger::INFO) # Use futile.logger::INFO
flog.info("--- Health Check Client Demo Starting ---")

# --- Define Paths and Read Service Definitions ---
helloworld_proto_path <- system.file('examples/helloworld.proto', package = 'grpc')
healthcheck_proto_path <- system.file('examples/health_check.proto', package = 'grpc')

if (helloworld_proto_path == "") stop("Could not find helloworld.proto in grpc package examples.")
if (healthcheck_proto_path == "") stop("Could not find health_check.proto in grpc package examples.")

flog.info("Reading service definitions from proto files...")
impl_for_stubs <- NULL
tryCatch({
  # These calls might give "already defined" RProtoBuf warnings if types
  # were pre-loaded by library(grpc) or library(RProtoBuf).
  # The key is whether it successfully returns the 'impl' structure needed by grpc_client.
  impl_helloworld_stubs <- grpc::read_services(helloworld_proto_path)
  impl_health_stubs <- grpc::read_services(healthcheck_proto_path)
  impl_for_stubs <- c(impl_helloworld_stubs, impl_health_stubs)
  flog.info("Names in combined impl_for_stubs: %s", paste(names(impl_for_stubs), collapse=", "))
}, error = function(e) {
  flog.error("Failed to read proto files for client stubs: %s", e$message)
  stop("Client stub creation prerequisite (read_services) failed.")
})

# --- Connect to Server ---
port_file <- "C:/Users/laurensvdb/grpc_health_check_server.port"
flog.info("Attempting to read server port from: %s", port_file)

if (!file.exists(port_file)) {
  flog.error("Port file '%s' not found. Please ensure the health-check-server demo is running first.", port_file)
  stop("Server port file not found.")
}
port <- readLines(port_file, n = 1, warn = FALSE)

if (length(port) == 0 || nchar(port) == 0) {
  flog.error("Port file '%s' is empty.", port_file)
  stop("Could not read port from file.")
}
port <- trimws(port)
server_address <- paste('localhost', port, sep = ':')
flog.info("Connecting to server at: %s", server_address)

client <- NULL
tryCatch({
  if (is.null(impl_for_stubs)) stop("Service implementation for client stubs ('impl_for_stubs') is NULL.")
  client <- grpc::grpc_client(impl_for_stubs, server_address)
}, error = function(e) {
  flog.error("Failed to create gRPC client: %s", e$message)
  stop("Client creation failed.")
})

# --- Verify Client Stub Names (Crucial Step) ---
# Based on previous evidence, expect simple names
simple_health_check_name <- "Check"  # From grpc.health.v1.Health service
simple_say_hello_name <- "SayHello" # From helloworld.Greeter service

required_simple_methods_client <- c(simple_health_check_name, simple_say_hello_name)

flog.info("Verifying client stub names. Expected: %s", paste(required_simple_methods_client, collapse=", "))
flog.info("Actual names in 'client' object: %s", paste(names(client), collapse=", "))

if (!all(required_simple_methods_client %in% names(client))) {
  missing_methods <- setdiff(required_simple_methods_client, names(client))
  flog.error("Client object missing expected simple methods: %s",
             paste(missing_methods, collapse=", "))
  stop("Client object structure incorrect. Adjust simple_..._name variables based on 'Actual names'.")
}

# --- Perform Health Check ---
flog.info("Performing health check (%s method)...", simple_health_check_name)
if (simple_health_check_name %in% names(client)) {
  tryCatch({
    # For standard health check, HealthCheckRequest field is 'service'
    health_request <- client[[simple_health_check_name]]$build(service = "") # Empty for overall health
    res_check <- client[[simple_health_check_name]]$call(health_request)
    flog.info("Health Check Response:")
    print(res_check) # Print the RProtoBuf object

    # Assuming res_check is HealthCheckResponse with 'status' field (enum)
    # grpc.health.v1.HealthCheckResponse.ServingStatus enum: UNKNOWN=0, SERVING=1, NOT_SERVING=2
    status_val <- res_check$status
    if (is.null(status_val)) {
      flog.warn("Health check response missing 'status' field.")
    } else if (status_val == 1) { # SERVING
      flog.info("Server status: SERVING")
    } else {
      flog.warn("Server status is not SERVING (status code: %s)", status_val)
    }
  }, error = function(e) {
    flog.error("Health check call to '%s' failed: %s", simple_health_check_name, e$message)
  })
} else {
  flog.warn("Method stub '%s' not found in client object.", simple_health_check_name)
}


# --- Perform SayHello RPC Call ---
flog.info("Performing SayHello RPC call (%s method)...", simple_say_hello_name)
if (simple_say_hello_name %in% names(client)) {
  tryCatch({
    hello_request <- client[[simple_say_hello_name]]$build(name = 'R Health Demo User')
    res_hello <- client[[simple_say_hello_name]]$call(hello_request)
    flog.info("SayHello Response:")
    print(res_hello)
  }, error = function(e) {
    flog.error("SayHello call to '%s' failed: %s", simple_say_hello_name, e$message)
    # stop("SayHello RPC failed.") # Decide if fatal
  })
} else {
  flog.warn("Method stub '%s' not found in client object.", simple_say_hello_name)
}

flog.info("--- Health Check Client Demo Finished ---")
