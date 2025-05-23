# SCRIPT FOR R SESSION 2: CLIENT
# Purpose: Connects to the gRPC server (started in Session 1) and makes a call.

# 0. Load necessary libraries
#library(grpc)        # Your package
library(RProtoBuf)   # For P() and message manipulation
library(futile.logger) # For logging

flog.threshold(DEBUG) # Set desired log level

# 1. Load Protocol Buffer Definitions (must match server session)
proto_file_path <- system.file("examples/helloworld.proto", package = "grpc")
if (proto_file_path == "") {
  proto_file_path_dev <- "inst/examples/helloworld.proto" # Relative to your package root
  if (file.exists(proto_file_path_dev)) {
    proto_file_path <- proto_file_path_dev
  } else {
    stop("CLIENT: helloworld.proto not found. Check path and package installation/loading.")
  }
}
flog.info("CLIENT: Using proto file: %s", proto_file_path)
readProtoFiles(dir = dirname(proto_file_path), pattern = basename(proto_file_path))
flog.info("CLIENT: Proto files read.")

# 2. MANUALLY ENTER THE PORT NUMBER observed from Server Session 1's C++ logs
#    Example: If server logged "listening on port 59281", set it to 59281.
MANUALLY_ENTERED_PORT <- 52168  # !!! --- REPLACE 59281 WITH THE ACTUAL PORT --- !!!

if (!is.numeric(MANUALLY_ENTERED_PORT) || is.na(MANUALLY_ENTERED_PORT) || MANUALLY_ENTERED_PORT <= 0 || MANUALLY_ENTERED_PORT > 65535) {
  stop("CLIENT: Invalid MANUALLY_ENTERED_PORT. Please set it to the integer port number from the server's log.")
}
flog.info("CLIENT: Will attempt to connect to port: %d", MANUALLY_ENTERED_PORT)

# 3. Prepare Client Call Arguments
server_host_and_port <- paste0("localhost:", MANUALLY_ENTERED_PORT)
grpc_method_path <- "/helloworld.Greeter/SayHello" # Fully qualified

# Create the request message object
request_name_sent_by_client <- "R Client via C++ Call" # Store the name you send
request_message <- RProtoBuf::new(P("helloworld.GreetingRequest"), name = request_name_sent_by_client)

# Serialize the request message to raw bytes
serialized_request_payload <- RProtoBuf::serialize(request_message, NULL)

expected_reply_from_server <- "Hello from Robust C-Core Server!"
expected_r_handler_reply <- paste("R says hello to", request_name_sent_by_client) # THIS IS THE FIX
client_call_successful <- FALSE

# 4. Execute the gRPC Call using the C++ client function
flog.info("CLIENT: Preparing to call C++ function 'robust_grpc_client_call'.")
flog.info("CLIENT: Target: '%s', Method: '%s'", server_host_and_port, grpc_method_path)

tryCatch({
  # This calls your Rcpp-exported C++ function
  raw_response_payload <- robust_grpc_client_call(
    r_target_str = server_host_and_port,
    r_method_str = grpc_method_path,
    r_request_payload = serialized_request_payload,
    r_metadata = list() # r_metadata = list("my-client-key", "my-client-value") # Optional metadata
  )

  # In client script, after getting raw_response_payload
  if (!is.null(raw_response_payload) && length(raw_response_payload) > 0) {
    # Expecting a GreetingReply now
    reply_msg_from_server <- RProtoBuf::read(P("helloworld.GreetingReply"), raw_response_payload)
    flog.info("CLIENT: Deserialized reply message: '%s'", reply_msg_from_server$message)

    if (reply_msg_from_server$message == expected_r_handler_reply) {
      flog.info("CLIENT: SUCCESS! Received expected reply from the R handler via C++ server.")
      client_call_successful <- TRUE
    } else {
      flog.error("CLIENT: FAILED! Reply mismatch from R handler. Expected: '%s', Got: '%s'",
                 expected_r_handler_reply, reply_msg_from_server$message)
    }
  }

}, error = function(e) {
  flog.error("CLIENT: An error occurred during 'robust_grpc_client_call': %s", e$message)
  flog.info("CLIENT: Make sure the server (Session 1) is still running and listening on port %d.", MANUALLY_ENTERED_PORT)
  flog.info("CLIENT: The server is set to run for %d seconds.", 60) # Assuming 60s from server script
})

# 5. Report Final Test Outcome
if (client_call_successful) {
  flog.info(">>>> Client Test (Manual Port): PASSED <<<<")
} else {
  flog.error(">>>> Client Test (Manual Port): FAILED <<<<")
}
