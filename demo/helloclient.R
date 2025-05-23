#' Hello World Client Demo
#'
#' Connects to the HelloWorld gRPC server (expected to be running
#' on localhost:50051) and calls the SayHello, SayThanks, and SayBye methods.
#' Note: Requires the 'helloserver' demo to be running on port 50051.
#' @demo helloclient
#' @importFrom futile.logger flog.info flog.error flog.threshold
#' @importFrom RProtoBuf P new # For building request messages directly if needed

# --- Setup ---
library(grpc)
library(RProtoBuf)
library(futile.logger)

flog.threshold(futile.logger::INFO) # Use futile.logger::INFO for the constant
flog.info("--- Hello World Client Demo Starting ---")

# --- Define Paths and Read Service Definitions ---
spec_path <- system.file('examples/helloworld.proto', package = 'grpc')
if (spec_path == "") {
  flog.fatal("Could not find helloworld.proto in installed grpc package examples.")
  stop("Could not find helloworld.proto.")
}

flog.info("Reading service definition from installed package: %s", spec_path)
impl_for_client_stubs <- NULL
tryCatch({
  # This call might still produce "already defined" RProtoBuf warnings if types
  # were pre-loaded by library(grpc) or library(RProtoBuf).
  # However, the key is whether it successfully returns the 'impl' structure needed by grpc_client.
  impl_for_client_stubs <- grpc::read_services(spec_path)
}, error = function(e) {
  flog.error("Failed to read proto file '%s' for client stubs: %s", spec_path, e$message)
  stop("Client stub creation prerequisite (read_services) failed.")
})

# --- Connect to Server ---
server_address <- "localhost:50051" # Server demo hardcodes this port
flog.info("Attempting to connect to server at: %s", server_address)
flog.info("(Ensure the 'helloserver' demo is running on this port).")

client <- NULL
tryCatch({
  if (is.null(impl_for_client_stubs)) stop("Service implementation for client stubs ('impl_for_client_stubs') is NULL.")
  client <- grpc::grpc_client(impl_for_client_stubs, server_address)
}, error = function(e) {
  flog.error("Failed to create gRPC client for '%s': %s", server_address, e$message)
  stop("Client creation failed. Is the server running?")
})

# --- Verify Client Stub Names (Crucial Step) ---
# Based on server-side log, we now expect simple names.
simple_method_sayhello <- "SayHello"
simple_method_saythanks <- "SayThanks"
simple_method_saybye <- "SayBye"

required_simple_methods_client <- c(simple_method_sayhello, simple_method_saythanks, simple_method_saybye)

flog.info("Verifying client stub names. Expected: %s", paste(required_simple_methods_client, collapse=", "))
flog.info("Actual names in 'client' object: %s", paste(names(client), collapse=", "))

if (!all(required_simple_methods_client %in% names(client))) {
  missing_methods <- setdiff(required_simple_methods_client, names(client))
  flog.error("Client object missing expected simple methods: %s",
             paste(missing_methods, collapse=", "))
  stop("Client object structure incorrect. Method names in client stubs do not match expectation.")
}

# --- Make RPC Calls ---
names_to_greet <- c("Neal", "Gergely", "Jay", "World")

for(who in names_to_greet) {
  flog.info("--- Calling RPC methods for name: %s ---", who)

  # 1. SayHello Call
  tryCatch({
    flog.info("Calling %s...", simple_method_sayhello)
    # Use direct $ access now that we assume simple names
    hello_req <- client[[simple_method_sayhello]]$build(name = who)
    hello_resp <- client[[simple_method_sayhello]]$call(hello_req)
    flog.info("%s Response:", simple_method_sayhello)
    print(hello_resp)
  }, error = function(e) {
    flog.error("%s call failed for name '%s': %s", simple_method_sayhello, who, e$message)
  })

  # 2. SayThanks Call (with metadata)
  tryCatch({
    flog.info("Calling %s (with metadata)...", simple_method_saythanks)
    thanks_req <- client[[simple_method_saythanks]]$build(name = who)
    req_metadata <- c("client-source", "R-demo", "request-id", format(Sys.time(), "%Y%m%d%H%M%S"))
    thanks_resp <- client[[simple_method_saythanks]]$call(thanks_req, metadata = req_metadata)
    flog.info("%s Response:", simple_method_saythanks)
    print(thanks_resp)
  }, error = function(e) {
    flog.error("%s call failed for name '%s': %s", simple_method_saythanks, who, e$message)
  })

  # 3. SayBye Call
  tryCatch({
    flog.info("Calling %s...", simple_method_saybye)
    bye_req <- client[[simple_method_saybye]]$build(name = who)
    bye_resp <- client[[simple_method_saybye]]$call(bye_req)
    flog.info("%s Response:", simple_method_saybye)
    print(bye_resp)
  }, error = function(e) {
    flog.error("%s call failed for name '%s': %s", simple_method_saybye, who, e$message)
  })

  Sys.sleep(0.1)
}

flog.info("--- Hello World Client Demo Finished ---")
