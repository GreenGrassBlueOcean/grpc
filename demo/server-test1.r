# SCRIPT FOR R SESSION 1: SERVER (server-test1.r)
# Assumes .onLoad in the grpc package now handles loading helloworld.proto

# library(grpc) # Not needed if devtools::load_all(".") was run
library(RProtoBuf)
library(futile.logger)

flog.threshold(DEBUG)

# Protos should have been loaded by 'devtools::load_all(".")' via your .onLoad function.
flog.info("SERVER: Verifying proto types are available after package load (via .onLoad)...")
REQ_DESC_TEST <- NULL
REP_DESC_TEST <- NULL
proto_types_loaded_ok <- FALSE
tryCatch({
  REQ_DESC_TEST <- RProtoBuf::P("helloworld.GreetingRequest")
  REP_DESC_TEST <- RProtoBuf::P("helloworld.GreetingReply")
  if (is(REQ_DESC_TEST, "Descriptor") && is(REP_DESC_TEST, "Descriptor")) {
    flog.info("SERVER: helloworld.GreetingRequest and helloworld.GreetingReply descriptors successfully retrieved.")
    proto_types_loaded_ok <- TRUE
  } else {
    flog.error("SERVER: P() did not return valid descriptors. Check .onLoad.")
  }
}, error = function(e) {
  flog.error("SERVER: Error retrieving protobuf descriptors: %s. Check .onLoad.", e$message)
})

if (!proto_types_loaded_ok) {
  stop("SERVER: Protobuf message types were not correctly made available by the package. Halting.")
}

dummy_r_handler_function <- function(request) { # request is the deserialized RProtoBuf object
  flog.info("SERVER DUMMY HANDLER: Request name: %s", request$name)

  # Get the attribute FROM THE CURRENT FUNCTION (f_with_attrs)
  current_function_object <- sys.function() # Gets the currently executing function
  response_descriptor <- attr(current_function_object, "ResponseTypeDescriptor")

  if (is.null(response_descriptor) || !is(response_descriptor, "Descriptor")) {
    flog.error("SERVER DUMMY HANDLER: Could not retrieve valid ResponseTypeDescriptor attribute from myself.")
    # This would be a critical error in how attributes were set.
    # For now, let's try to fall back or error, but ideally this check passes.
    # Fallback (less ideal, assumes it's globally available and correct):
    # response_descriptor <- RProtoBuf::P("helloworld.GreetingReply")
    stop("SERVER DUMMY HANDLER: Failed to get ResponseTypeDescriptor attribute.")
  }

  flog.info("SERVER DUMMY HANDLER: Using ResponseTypeDescriptor of class: %s", paste(class(response_descriptor), collapse=", "))
  RProtoBuf::new(response_descriptor, message = paste("R says hello to", request$name))
}

dummy_impl_argument_for_r_wrapper <- list(
  SayHello = list(
    name = "/helloworld.Greeter/SayHello",
    RequestType = REQ_DESC_TEST,
    ResponseType = REP_DESC_TEST,
    f = dummy_r_handler_function
  )
)
flog.info("SERVER: Dummy 'impl' argument prepared.")

minimal_hooks_argument_for_r_wrapper <- list(
  exit = function() { flog.info("SERVER: R 'start_server' function's on.exit hook called.") }
)
flog.info("SERVER: Minimal 'hooks' argument prepared.")

server_listen_address <- "localhost:0"
server_run_duration_seconds <- 600

flog.info("SERVER: Attempting to start gRPC server on '%s' for %d seconds...",
          server_listen_address, server_run_duration_seconds)
flog.info("SERVER: >>> IMPORTANT: Watch the C++ logs below for the line <<<")
flog.info("SERVER: >>> '[gRPC Debug] (server.cpp:XX) Robust Server: Started, listening on port YYYYY' <<<")
flog.info("SERVER: >>> Note down the YYYYY port number for the client session. <<<")

port_file_for_hooks <- "server_hook.port" # Define for bind hook
if(file.exists(port_file_for_hooks)) file.remove(port_file_for_hooks)

active_hooks <- list(
  server_create = function() { flog.info("R_HOOK: server_create called") },
  queue_create = function() { flog.info("R_HOOK: queue_create called") },
  bind = function(params) {
    flog.info("R_HOOK: bind called with port: %s", params$port)
    if (!is.null(params$port) && params$port > 0) {
      cat(params$port, file = port_file_for_hooks)
      flog.info("R_HOOK: bind - port written to %s", port_file_for_hooks)
    }
  },
  server_start = function() { flog.info("R_HOOK: server_start called") },
  run = function() { flog.info("R_HOOK: run called (main loop starting)") },
  shutdown = function() { flog.info("R_HOOK: shutdown called") },
  stopped = function() { flog.info("R_HOOK: stopped called") },
  exit = function() { # This is R's on.exit from start_server
    flog.info("R_HOOK: exit (from R on.exit) called")
    if (file.exists(port_file_for_hooks)) file.remove(port_file_for_hooks)
  }
)


# This call invokes your R 'start_server' function, which should in turn call
# the C++ 'robust_grpc_server_run' function. This will block R for 'server_run_duration_seconds'.
grpc::start_server(
  impl = dummy_impl_argument_for_r_wrapper,
  channel = server_listen_address,
  hooks = active_hooks, # minimal_hooks_argument_for_r_wrapper,
  duration_seconds = server_run_duration_seconds # Make sure your R 'start_server' accepts this
)

flog.info("SERVER: C++ server function has returned (duration elapsed or R interrupt).")
# The 'exit' hook from minimal_hooks_argument_for_r_wrapper should also fire now.
