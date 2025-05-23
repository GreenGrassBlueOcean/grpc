# --- Setup ---
library(grpc) # For the Rcpp::export to be callable via grpc::
library(RProtoBuf) # Only if you were to construct actual proto messages
library(futile.logger)

flog.threshold(futile.logger::INFO)
flog.info("--- Minimal C-Core Client Test Starting ---")

# --- Get Server Address ---
port_file <- "C:/Users/laurensvdb/grpc_health_check_server.port" # Make sure this is correct
flog.info("Attempting to read server port from: %s", port_file)

if (!file.exists(port_file)) {
  flog.error("Port file '%s' not found. Please ensure the health-check-server.R demo is running first.", port_file)
  stop("Server port file not found.")
}
port <- readLines(port_file, n = 1, warn = FALSE)

if (length(port) == 0 || nchar(port) == 0) {
  flog.error("Port file '%s' is empty.", port_file)
  stop("Could not read port from file.")
}
port <- trimws(port)
# server_address <- paste('localhost', port, sep = ':')
server_address <- paste('127.0.0.1', port, sep = ':') # Try with explicit 127.0.0.1 first
flog.info("Will connect to server at: %s", server_address)

# --- Define Method and Dummy Payload ---
# The server's minimal_loop will respond with UNIMPLEMENTED for any method.
# We just need a valid-looking method string and some payload.
target_method <- "/helloworld.Greeter/SayHello" # Or any method string
# For this C-core test, the actual content of request_payload doesn't matter much
# as the server isn't parsing it before replying UNIMPLEMENTED.
# Sending a simple string converted to raw.
request_data_raw <- charToRaw("Test R User")

flog.info("Attempting RPC to method: %s", target_method)

# --- Call the C++ function ---
# Ensure your package is loaded so R can find minimal_grpc_call_c_core
# If running interactively after devtools::load_all(".") or Build & Install, it should be.
# If running as a standalone script, you might need library(yourpackagename)
response_payload <- NULL
call_status <- "Unknown"

tryCatch({
  # The minimal_grpc_call_c_core function expects:
  # 1. CharacterVector server_address_r
  # 2. CharacterVector method_r
  # 3. RawVector request_payload_r
  # (It doesn't take metadata in this simplified version)
  
  # Call the exported function (it will be grpc::minimal_grpc_call_c_core if package is 'grpc')
  response_payload <- grpc::minimal_grpc_call_c_core(
    server_address,
    target_method,
    request_data_raw
  )
  
  call_status <- "SUCCESS (Call returned, check payload)"
  flog.info("RPC call returned. Response payload length: %d", length(response_payload))
  if (length(response_payload) > 0) {
    flog.info("Response (first 50 bytes as hex): %s", paste(as.character(response_payload[1:min(50, length(response_payload))]), collapse=" "))
    # You would typically try to parse this with RProtoBuf if it were a real protobuf message
  } else {
    flog.info("Response payload is empty.")
  }
  
}, error = function(e) {
  call_status <- "ERROR"
  flog.error("RPC call failed: %s", e$message)
  # The C++ stop() messages should appear here
})

flog.info("Call attempt status: %s", call_status)
flog.info("--- Minimal C-Core Client Test Finished ---")