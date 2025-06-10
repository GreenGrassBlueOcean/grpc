# SCRIPT FOR R SESSION 2: CLIENT (client-test2.r)
# Purpose: Tests the revised grpc_client R wrapper against the server.

# 0. Load necessary libraries
library(RProtoBuf)
library(futile.logger)
#library(grpc) # Use devtools::load_all(".") OR library(grpc) consistently

# EXPLICITLY LOAD PROTO DEFINITIONS IN THIS SESSION
proto_file_for_client_session <- system.file('examples/helloworld.proto', package = 'grpc')
if (nzchar(proto_file_for_client_session)) {
  RProtoBuf::readProtoFiles(proto_file_for_client_session)
  futile.logger::flog.info("CLIENT_SESSION: Explicitly called RProtoBuf::readProtoFiles on '%s'", proto_file_for_client_session)
} else {
  stop("CLIENT_SESSION: Could not find helloworld.proto for explicit loading in client session.")
}

# Before loading grpc or running gRPC operations
# rgrpc_set_core_logging(trace_options = c("client"), verbosity = "INFO") # Keep this off for now

flog.threshold(DEBUG)

# 1. Read Service Definitions using read_services
flog.info("CLIENT: Reading service definitions from helloworld.proto using read_services...")
# services_spec_file_client is already defined above as proto_file_for_client_session
client_service_spec <- read_services(proto_file_for_client_session) # read_services will call readProtoFiles again; this is redundant but should be harmless
flog.info("CLIENT: Service definitions read.")

# (The manual proto descriptor verification block can be removed as read_services
#  would error if RProtoBuf::P failed to find the descriptors.)

# 2. MANUALLY ENTER THE PORT NUMBER
# (This part remains manual or could read from server_hook.port if server-test1 wrote it reliably)
MANUALLY_ENTERED_PORT <- 60472 # !!! --- REPLACE WITH THE ACTUAL PORT FROM YOUR SERVER LOG --- !!!
port_file_for_client <- "server_hook.port" # Match the file name from server-test1.r
if (file.exists(port_file_for_client)) {
  flog.info("CLIENT: Attempting to read port from '%s'", port_file_for_client)
  port_from_file <- suppressWarnings(as.integer(readLines(port_file_for_client, n=1)))
  if (!is.na(port_from_file) && port_from_file > 0 && port_from_file <= 65535) {
    MANUALLY_ENTERED_PORT <- port_from_file
    flog.info("CLIENT: Using port %d read from file.", MANUALLY_ENTERED_PORT)
  } else {
    flog.warn("CLIENT: Could not read a valid port from '%s'. Using hardcoded port: %d.",
              port_file_for_client, MANUALLY_ENTERED_PORT)
  }
} else {
  flog.warn("CLIENT: Port file '%s' not found. Using hardcoded port: %d. Ensure server is running and wrote the port file.",
            port_file_for_client, MANUALLY_ENTERED_PORT)
}


if (!is.numeric(MANUALLY_ENTERED_PORT) || is.na(MANUALLY_ENTERED_PORT) || MANUALLY_ENTERED_PORT <= 0 || MANUALLY_ENTERED_PORT > 65535) {
  stop(paste("CLIENT: Invalid port number:", MANUALLY_ENTERED_PORT,
             "Please ensure the server (Session 1) is running and its port is correctly set (e.g., via server_hook.port or manually)."))
}
flog.info("CLIENT: Will attempt to connect to port: %d", MANUALLY_ENTERED_PORT)
client_target_address <- paste0("localhost:", MANUALLY_ENTERED_PORT)


# 3. Create the client stub using your package's grpc_client function
# 'client_service_spec' from read_services now has the correct structure.
flog.info("CLIENT: Creating client stub using grpc::grpc_client...")
greeter_client <- NULL
tryCatch({
  greeter_client <- grpc::grpc_client(services = client_service_spec, channel = client_target_address)
  flog.info("CLIENT: Client stub created successfully.")
}, error = function(e) {
  flog.error("CLIENT: Failed to create client stub: %s", e$message)
  stop("Client stub creation failed. Ensure server is running and client_service_spec is correct.")
})

# 4. Prepare the request and expected response
request_name_val <- "R gRPC User via Simplified Client Stub"
# This expected message should match what dummy_r_handler_function in server-test1.r produces
expected_r_handler_reply_message <- paste("R says hello to", request_name_val)
client_test_final_status <- FALSE

# 5. Execute the RPC using the client stub
# Ensure "SayHello" matches the method name in your .proto file (case-sensitive for the list key)
if (!is.null(greeter_client) && !is.null(greeter_client$SayHello)) {
  tryCatch({
    flog.info("CLIENT: Building request message using stub$SayHello$build()...")
    request_message_object <- greeter_client$SayHello$build(name = request_name_val)
    flog.info("CLIENT: Request object built: %s", RProtoBuf::toString(request_message_object))

    flog.info("CLIENT: Calling server using stub$SayHello$call()...")
    response_message_object <- greeter_client$SayHello$call(
      request_message_object,
      metadata = list("client-source", "R-simplified-client-test") # Example metadata
    )

    flog.info("CLIENT: Received and deserialized response. Message content: '%s'", response_message_object$message)

    if (response_message_object$message == expected_r_handler_reply_message) {
      flog.info("CLIENT: SUCCESS! Received expected reply from the R handler via client stub.")
      client_test_final_status <- TRUE
    } else {
      flog.error("CLIENT: FAILED! Reply mismatch. Expected: '%s', Got: '%s'",
                 expected_r_handler_reply_message, response_message_object$message)
    }

  }, error = function(e) {
    flog.error("CLIENT: An error occurred during the stub call: %s", e$message)
    flog.info("CLIENT: Ensure the server (Session 1) is still running and listening on port %d.", MANUALLY_ENTERED_PORT)
  })
} else {
  flog.error("CLIENT: greeter_client stub or $SayHello method not found. Check grpc_client() setup and .proto method names.")
}

# 6. Report Final Test Outcome
if (client_test_final_status) {
  flog.info(">>>> Client Test (simplified, using grpc_client stub): PASSED <<<<")
} else {
  flog.error(">>>> Client Test (simplified, using grpc_client stub): FAILED <<<<")
}

rgrpc_set_core_logging(trace_options = NULL, verbosity = NULL)
