# SCRIPT FOR R SESSION 1: SERVER (server-test1.r)
# Assumes .onLoad in the grpc package now handles loading helloworld.proto

#library(grpc) # Not needed if devtools::load_all(".") was run
library(RProtoBuf)
library(futile.logger)

# Before loading grpc or running gRPC operations
#rgrpc_set_core_logging(trace_options = c("all"), verbosity = "DEBUG")
rgrpc_set_core_logging(trace_options = NULL, verbosity = NULL)

flog.threshold(INFO)



flog.info("SERVER: Reading service definitions from helloworld.proto using read_services...")

services_spec_file <- system.file('examples/helloworld.proto', package = 'grpc')
if (!nzchar(services_spec_file)) {
  stop("SERVER: Could not find helloworld.proto. Check package installation and inst/examples.")
}
impl <- read_services(services_spec_file) # Renamed to 'impl' for clarity, common usage
flog.info("SERVER: Service definitions read.")

# Step 2: Define the R handler function for the RPC method
dummy_r_handler_function <- function(request) { # request is the deserialized RProtoBuf object
  flog.info("SERVER DUMMY HANDLER: Request name: %s", request$name)

  current_function_object <- sys.function()
  response_descriptor <- attr(current_function_object, "ResponseTypeDescriptor")

  if (is.null(response_descriptor) || !is(response_descriptor, "Descriptor")) {
    flog.error("SERVER DUMMY HANDLER: Could not retrieve valid ResponseTypeDescriptor attribute.")
    # This typically indicates an issue in how start_server prepares the handler.
    # If impl$SayHello$ResponseType was a valid Descriptor, start_server should set this attribute.
    stop("SERVER DUMMY HANDLER: Failed to get ResponseTypeDescriptor attribute.")
  }

  flog.info("SERVER DUMMY HANDLER: Using ResponseTypeDescriptor of class: %s", class(response_descriptor)[1])
  RProtoBuf::new(response_descriptor, message = paste("R says hello to", request$name))
}

# Step 3: Assign the handler function to the appropriate method in the 'impl' object
# Ensure the method name "SayHello" matches what's in your helloworld.proto and parsed by read_services
if ("SayHello" %in% names(impl)) {
  impl$SayHello$f <- dummy_r_handler_function
  flog.info("SERVER: Assigned dummy_r_handler_function to impl$SayHello$f.")
} else {
  stop("SERVER: Method 'SayHello' not found in 'impl' object from read_services. Check .proto and parser.R.")
}
# If you had other methods like SayThanks, SayBye in your proto, you would assign their 'f' here too:
# if ("SayThanks" %in% names(impl)) impl$SayThanks$f <- your_say_thanks_handler
# if ("SayBye" %in% names(impl)) impl$SayBye$f <- your_say_bye_handler

# Step 4: Define Hooks (already corrected by you to accept params)
# flog.info("SERVER: Preparing 'active_hooks'...") # No longer using 'minimal_hooks_argument_for_r_wrapper'
port_file_for_hooks <- "server_hook.port"
if(file.exists(port_file_for_hooks)) file.remove(port_file_for_hooks)

active_hooks <- list(
  server_create = function(params) { flog.info("R_HOOK (server-test1): server_create called") },
  queue_create = function(params) { flog.info("R_HOOK (server-test1): queue_create called") },
  bind = function(params) {
    flog.info("R_HOOK (server-test1): bind called with port: %s", params$port)
    if (!is.null(params$port) && params$port > 0) {
      cat(params$port, file = port_file_for_hooks)
      flog.info("R_HOOK (server-test1): bind - port written to %s", port_file_for_hooks)
    }
  },
  server_start = function(params) { flog.info("R_HOOK (server-test1): server_start called") },
  run = function(params) { flog.info("R_HOOK (server-test1): run called (main loop starting)") },
  shutdown = function(params) { flog.info("R_HOOK (server-test1): shutdown called") },
  stopped = function(params) { flog.info("R_HOOK (server-test1): stopped called") },
  exit = function() {
    flog.info("R_HOOK (server-test1): exit (from R on.exit) called")
    if (file.exists(port_file_for_hooks)) file.remove(port_file_for_hooks)
  }
)
flog.info("SERVER: 'active_hooks' prepared.")

# Step 5: Server Configuration
server_listen_address <- "localhost:0" # Use "0.0.0.0:0" to listen on all interfaces, dynamic port
server_run_duration_seconds <- 600

flog.info("SERVER: Attempting to start gRPC server on '%s' for %d seconds...",
          server_listen_address, server_run_duration_seconds)
flog.info("SERVER: >>> IMPORTANT: Watch the C++ logs for the line '[gRPC Debug] ... Robust Server: Started, listening on port YYYYY' <<<")
flog.info("SERVER: >>> Note down the YYYYY port number for the client session. <<<")


# Step 6: Start the Server
# This call invokes your R 'start_server' function
grpc::start_server(
  impl = impl, # Use the 'impl' object from read_services with the handler assigned
  channel = server_listen_address,
  hooks = active_hooks,
  duration_seconds = server_run_duration_seconds
)

flog.info("SERVER: C++ server function has returned (duration elapsed or R interrupt).")
# The 'exit' hook from active_hooks should also fire now.


# Or to turn them off
rgrpc_set_core_logging(NULL, NULL)
