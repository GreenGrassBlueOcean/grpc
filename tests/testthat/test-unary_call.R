# tests/testthat/test-unary_call.R

create_temp_helloworld_proto_test_r4_unary <- function(temp_dir = tempdir()) {
  test_package_name <- paste0("helloworldtest", sample.int(1e9,1))
  proto_content_template <- r"(
syntax = "proto3";
package {{TEST_PACKAGE_NAME}};
service TestGreeter {
  rpc SayTestHello (TestHelloRequest) returns (TestHelloReply) {}
}
message TestHelloRequest { string name = 1; }
message TestHelloReply { string message = 1; }
)"
proto_content <- gsub("{{TEST_PACKAGE_NAME}}", test_package_name, proto_content_template, fixed = TRUE)
proto_file_basename <- paste0("test_helloworld_r4_", test_package_name, ".proto")
proto_file <- file.path(temp_dir, proto_file_basename)
cat(proto_content, file = proto_file)
return(list(filepath = proto_file, packagename = test_package_name, servicename = "TestGreeter",
            methodname = "SayTestHello", requesttype = "TestHelloRequest", replytype = "TestHelloReply"))
}

test_that("A unary call can be made to a local server (R 4.0+)", {
  skip_on_cran()
  skip_if_not(getRversion() >= "4.0.0", "Raw strings and callr API benefit from R >= 4.0.0")
  if (!requireNamespace("futile.logger", quietly = TRUE)) {
    skip("futile.logger not available for test logging.")
  }

  temp_test_dir <- tempfile("grpc_test_unary_")
  dir.create(temp_test_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(temp_test_dir, recursive = TRUE, force = TRUE), add = TRUE)

  proto_details <- create_temp_helloworld_proto_test_r4_unary(temp_dir = temp_test_dir)
  proto_file_path_abs <- normalizePath(proto_details$filepath, winslash="/", mustWork = TRUE)

  server_script_file <- file.path(temp_test_dir, "server_script.R")
  port_file_path_abs <- normalizePath(file.path(temp_test_dir, "server_hook.port"), winslash="/", mustWork = FALSE)

  # Server code template (ASSUMED TO BE THE CORRECT ONE FROM PREVIOUS ITERATIONS)
  # This template uses all the {{...}} placeholders and its handler uses grpc::newResponse
  server_code_template <- r"(
# Server Script Content
suppressPackageStartupMessages(library(grpc))
suppressPackageStartupMessages(library(RProtoBuf))
suppressPackageStartupMessages(library(futile.logger))

# futile.logger::flog.threshold(TRACE) # Uncomment for server-side debug if needed

proto_file_server <- '{{PROTO_FILE_PATH_ABS}}'
SERVER_PORT_FILE <- '{{PORT_FILE_PATH_ABS}}'

tryCatch({
  RProtoBuf::readProtoFiles(proto_file_server)
  futile.logger::flog.info("Server: Successfully loaded test proto: %s", proto_file_server)
}, error = function(e_proto) {
  futile.logger::flog.fatal("Server: FAILED to load test proto '%s'. Error: %s", proto_file_server, e_proto$message)
  writeLines(paste0("SERVER_ERROR_PROTO_LOAD: ", gsub('\\n',' ', e_proto$message)), SERVER_PORT_FILE)
  stop(e_proto)
})

TEST_PACKAGE_NAME <- "{{TEST_PACKAGE_NAME}}"
SERVICE_NAME_SIMPLE <- "{{SERVICE_NAME}}"
METHOD_NAME_SIMPLE <- "{{METHOD_NAME}}"
# REQUEST_TYPE_NAME_SIMPLE <- "{{REQUEST_TYPE_NAME}}" # Not directly used in this handler
# REPLY_TYPE_NAME_SIMPLE <- "{{REPLY_TYPE_NAME}}"     # Not directly used in this handler

handler_for_test_method <- function(request_message_obj) {
  futile.logger::flog.info("Server Handler: Received name: '%s'", request_message_obj$name)
  # grpc::newResponse uses the ResponseTypeDescriptor attribute set by start_server
  # which comes from impl_for_server below (the unique TestHelloReply descriptor)
  response <- grpc::newResponse(message = paste("Response from Test Server to", request_message_obj$name))
  futile.logger::flog.info("Server Handler: Sending response: %s", RProtoBuf::toString(response))
  return(response)
}

services_from_file <- grpc::read_services(proto_file_server)
if (!METHOD_NAME_SIMPLE %in% names(services_from_file)) {
    writeLines(paste0("SERVER_ERROR_METHOD_NOT_FOUND: ", METHOD_NAME_SIMPLE), SERVER_PORT_FILE)
    stop(paste("Method name mismatch in server setup. Expected:", METHOD_NAME_SIMPLE))
}

impl_for_server <- list()
impl_for_server[[METHOD_NAME_SIMPLE]] <- list(
  f = handler_for_test_method,
  RequestType = services_from_file[[METHOD_NAME_SIMPLE]]$RequestType, # Unique Descriptor
  ResponseType = services_from_file[[METHOD_NAME_SIMPLE]]$ResponseType, # Unique Descriptor
  name = services_from_file[[METHOD_NAME_SIMPLE]]$name
)

active_server_hooks <- list(
  bind = function(params) {
    if (!is.null(params$port) && is.numeric(params$port) && params$port > 0) {
      writeLines(as.character(params$port), SERVER_PORT_FILE)
      futile.logger::flog.info("Server Hook: bind - port %d written to %s", params$port, SERVER_PORT_FILE)
    } else { writeLines("SERVER_ERROR_BIND_INVALID_PORT", SERVER_PORT_FILE) }
  }
)
server_address_to_listen <- "localhost:0"; server_duration <- 20
futile.logger::flog.info("Server: Starting on '%s' for %d s. Method: '%s'",
          server_address_to_listen, server_duration, impl_for_server[[METHOD_NAME_SIMPLE]]$name)
tryCatch({
  grpc::start_server(impl = impl_for_server, channel = server_address_to_listen,
                     hooks = active_server_hooks, duration_seconds = server_duration)
  futile.logger::flog.info("Server: start_server returned.")
}, error = function(e_grpc_run) {
  futile.logger::flog.error("Server: start_server FAILED: %s", e_grpc_run$message)
  writeLines(paste0("SERVER_ERROR_GRPC_RUN: ", gsub('\\n',' ', e_grpc_run$message)), SERVER_PORT_FILE)
  stop(e_grpc_run)
})
futile.logger::flog.info("Server: Exiting script.")
)"

server_code <- gsub("{{PROTO_FILE_PATH_ABS}}", proto_file_path_abs, server_code_template, fixed = TRUE)
server_code <- gsub("{{PORT_FILE_PATH_ABS}}", port_file_path_abs, server_code, fixed = TRUE)
server_code <- gsub("{{TEST_PACKAGE_NAME}}", proto_details$packagename, server_code, fixed = TRUE)
server_code <- gsub("{{SERVICE_NAME}}", proto_details$servicename, server_code, fixed = TRUE)
server_code <- gsub("{{METHOD_NAME}}", proto_details$methodname, server_code, fixed = TRUE)
# These are used by the server script template above indirectly via services_from_file for impl
# server_code <- gsub("{{REQUEST_TYPE_NAME}}", proto_details$requesttype, server_code, fixed = TRUE) # Not directly used in template
# server_code <- gsub("{{REPLY_TYPE_NAME}}", proto_details$replytype, server_code, fixed = TRUE)     # Not directly used in template
cat(server_code, file = server_script_file)

stdout_log_file <- file.path(temp_test_dir, "server_stdout.log")
stderr_log_file <- file.path(temp_test_dir, "server_stderr.log")
server_process <- callr::r_bg(
  function(script_to_source) { base::source(script_to_source, echo = FALSE, verbose = FALSE) },
  args = list(script_to_source = server_script_file),
  supervise = TRUE, stdout = stdout_log_file, stderr = stderr_log_file
)

actual_port <- NULL
futile.logger::flog.info(sprintf("Test: Waiting for server port file: %s", port_file_path_abs))
max_wait_port_loops <- 200 # ~20 seconds
for(i in 1:max_wait_port_loops) {
  Sys.sleep(0.1)
  if(!server_process$is_alive()) {
    stdout_content <- if(file.exists(stdout_log_file)) paste(readLines(stdout_log_file, warn=FALSE), collapse="\n") else "Stdout log missing."
    stderr_content <- if(file.exists(stderr_log_file)) paste(readLines(stderr_log_file, warn=FALSE), collapse="\n") else "Stderr log missing."
    port_file_err_content <- if(file.exists(port_file_path_abs)) paste(readLines(port_file_path_abs, warn=FALSE), collapse="\n") else "Port file missing."
    stop(paste("Server process died prematurely. Exit code:", server_process$get_exit_status(),
               "\n--- Port File Content ---\n", port_file_err_content,
               "\n--- Server Stdout ---\n", stdout_content,
               "\n--- Server Stderr ---\n", stderr_content))
  }
  if(file.exists(port_file_path_abs) && file.size(port_file_path_abs) > 0) {
    port_content_lines <- readLines(port_file_path_abs, n=1, warn = FALSE)
    if (length(port_content_lines) > 0 && grepl("^SERVER_ERROR", port_content_lines[1])) {
      Sys.sleep(0.2); stdout_content <- if(file.exists(stdout_log_file)) paste(readLines(stdout_log_file, warn=FALSE), collapse="\n") else "Stdout log missing."
      stderr_content <- if(file.exists(stderr_log_file)) paste(readLines(stderr_log_file, warn=FALSE), collapse="\n") else "Stderr log missing."
      stop(paste("Server reported error in port file:", port_content_lines[1],
                 "\n--- Server Stdout ---\n", stdout_content,
                 "\n--- Server Stderr ---\n", stderr_content))
    }
    parsed_port <- suppressWarnings(as.integer(port_content_lines[1]))
    if(!is.na(parsed_port) && parsed_port > 0) {
      actual_port <- parsed_port; futile.logger::flog.info(sprintf("Test: Server port %d read from file.", actual_port)); break
    }
  }
}

if(is.null(actual_port)) {
  if (server_process$is_alive()) server_process$kill()
  stdout_content <- if(file.exists(stdout_log_file)) paste(readLines(stdout_log_file, warn=FALSE), collapse="\n") else "Stdout log missing."
  stderr_content <- if(file.exists(stderr_log_file)) paste(readLines(stderr_log_file, warn=FALSE), collapse="\n") else "Stderr log missing."
  port_file_content <- if(file.exists(port_file_path_abs)) paste(readLines(port_file_path_abs, warn=FALSE), collapse="\n") else "Port file missing/empty."
  stop(paste("Server did not write a valid port to file in time.",
             "\n--- Port File Content ---\n", port_file_content,
             "\n--- Server Stdout ---\n", stdout_content,
             "\n--- Server Stderr ---\n", stderr_content))
}

client_channel_str <- paste0("localhost:", actual_port)
futile.logger::flog.info(sprintf("Test: Client connecting to %s", client_channel_str))

# Client needs to load the same uniquely named proto file for its RProtoBuf environment
expect_silent(RProtoBuf::readProtoFiles(proto_file_path_abs))

client_services_def <- NULL
# Use grpc::read_services which should now provide RequestType/ResponseType as Descriptors
# and also RequestTypeName/ResponseTypeName as FQN strings.
expect_silent(client_services_def <- grpc::read_services(proto_file_path_abs))

greeter_client <- NULL
Sys.sleep(0.5)
# grpc_client uses the Descriptors from client_services_def
expect_silent(greeter_client <- grpc::grpc_client(services = client_services_def, channel = client_channel_str))

method_to_call_client <- proto_details$methodname
expect_true(method_to_call_client %in% names(greeter_client),
            info = paste("Method", method_to_call_client, "not in stubs:", paste(names(greeter_client), collapse=", ")))

request_client_name <- "Testthat R4 GRPC Client"

request_msg <- NULL
expect_silent(request_msg <- greeter_client[[method_to_call_client]]$build(name = request_client_name))

if (!is.null(request_msg)) {
  futile.logger::flog.info("Test: Class of request_msg from client build: %s", paste(class(request_msg), collapse=", "))
} else {
  stop("request_msg was NULL after build")
}

expect_true(is.object(request_msg), info = "request_msg should be an S3 object")
expect_true(inherits(request_msg, "Message"),
            info = paste("request_msg should inherit from 'Message'. Actual class:", paste(class(request_msg), collapse=", ")))

# MODIFIED ASSERTION for dynamically loaded unique protos:
# Check that the simple name of the message's internal descriptor matches the expected simple name.
req_msg_internal_descriptor <- RProtoBuf::descriptor(request_msg)
expect_false(is.null(req_msg_internal_descriptor), info = "Internal descriptor of request_msg is NULL")
if(!is.null(req_msg_internal_descriptor)){
  expect_equal(RProtoBuf::name(req_msg_internal_descriptor), proto_details$requesttype, # proto_details$requesttype is simple name
               info = paste("Simple name of request_msg's descriptor mismatch. Expected:", proto_details$requesttype,
                            "Actual:", RProtoBuf::name(req_msg_internal_descriptor)))
}

response_msg <- NULL
max_rpc_retries <- 3
for (attempt in 1:max_rpc_retries) {
  tryCatch({
    response_msg <- greeter_client[[method_to_call_client]]$call(request_msg)
    break
  }, error = function(e) {
    futile.logger::flog.warn(sprintf("Test: Client call attempt %d to %s failed: %s", attempt, client_channel_str, e$message))
    if (attempt == max_rpc_retries) {
      stdout_content <- if(file.exists(stdout_log_file)) paste(readLines(stdout_log_file, warn=FALSE), collapse="\n") else "Stdout log missing."
      stderr_content <- if(file.exists(stderr_log_file)) paste(readLines(stderr_log_file, warn=FALSE), collapse="\n") else "Stderr log missing."
      stop(paste("All client call attempts failed. Last error:", e$message,
                 "\n--- Server Stdout ---\n", stdout_content,
                 "\n--- Server Stderr ---\n", stderr_content))
    }
    Sys.sleep(0.5 * attempt)
  })
}

if(!is.null(response_msg)) {
  futile.logger::flog.info("Test: Class of response_msg from server: %s", paste(class(response_msg), collapse=", "))
} else {
  stop("response_msg was NULL after RPC call")
}
expect_true(is.object(response_msg), info = "response_msg should be an S3 object")
expect_true(inherits(response_msg, "Message"),
            info = paste("Response msg should inherit from 'Message'. Actual class:", paste(class(response_msg), collapse=", ")))

# MODIFIED ASSERTION for dynamically loaded unique protos:
res_msg_internal_descriptor <- RProtoBuf::descriptor(response_msg)
expect_false(is.null(res_msg_internal_descriptor), info = "Internal descriptor of response_msg is NULL")
if(!is.null(res_msg_internal_descriptor)){
  expect_equal(RProtoBuf::name(res_msg_internal_descriptor), proto_details$replytype, # proto_details$replytype is simple name
               info = paste("Simple name of response_msg's descriptor mismatch. Expected:", proto_details$replytype,
                            "Actual:", RProtoBuf::name(res_msg_internal_descriptor)))
}

expected_response_text <- paste("Response from Test Server to", request_client_name)
expect_equal(response_msg$message, expected_response_text)

futile.logger::flog.info("Test: Waiting for server process to terminate (due to duration_seconds).")
server_wait_start_time <- Sys.time()
while(server_process$is_alive() && (difftime(Sys.time(), server_wait_start_time, units="secs") < 25)) {
  Sys.sleep(0.2)
}
if (server_process$is_alive()) {
  futile.logger::flog.warn("Test: Server process did not self-terminate, killing.")
  server_process$kill()
}
server_exit_status <- server_process$get_exit_status()
futile.logger::flog.info(sprintf("Test: Server exit status: %s", if(is.null(server_exit_status)) "NULL (killed)" else server_exit_status))
})
