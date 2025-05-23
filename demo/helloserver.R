#' Hello World Server Demo
#'
#' Starts a gRPC server implementing the Greeter service (SayHello, SayThanks, SayBye)
#' from helloworld.proto, listening on port 50051 on all interfaces.
#' @demo helloserver
#' @importFrom futile.logger flog.info flog.error flog.threshold FATAL
#' @importFrom RProtoBuf P new # For new() and P()
#' @importFrom methods is # For type checking if needed

# --- Setup ---
library(grpc)
library(RProtoBuf)
library(futile.logger)

# Use futile.logger::INFO for the constant value
flog.threshold(futile.logger::INFO)

flog.info("--- Hello World Server Demo Starting ---")

# --- Define Paths and Read Service Definitions ---
spec_path <- system.file('examples/helloworld.proto', package = 'grpc')

if (spec_path == "") { # system.file returns "" if not found
  flog.fatal("Could not find helloworld.proto in grpc package examples.")
  stop("Could not find helloworld.proto.")
}

flog.info("Reading service definition from: %s", spec_path)
impl <- NULL
tryCatch({
  impl <- grpc::read_services(spec_path)
}, error = function(e) {
  flog.error("Failed to read proto file '%s': %s", spec_path, e$message)
  stop("Proto file reading failed.")
})

# --- Implement Service Methods ---
# Use the simple names that read_services ACTUALLY provides:
hello_method_name <- "SayHello"
thanks_method_name <- "SayThanks"
bye_method_name <- "SayBye"

required_methods <- c(hello_method_name, thanks_method_name, bye_method_name)
if (!all(required_methods %in% names(impl))) {
  missing_methods <- setdiff(required_methods, names(impl))
  flog.error("Implementation object missing expected methods: %s",
             paste(missing_methods, collapse=", "))
  flog.info("Actual names in 'impl': %s", paste(names(impl), collapse=", ")) # Keep this for debugging
  stop("Implementation object structure incorrect. Method names mismatch.")
}

# Get Response Message Descriptors using the simple method name
# (assuming all methods in this service use the same request/response types as per helloworld.proto)
GreetingReplyDescriptor <- impl[[hello_method_name]]$ResponseType$proto # Or P("helloworld.GreetingReply") directly
if(is.null(GreetingReplyDescriptor)) {
  # If ResponseType$proto is not populated as expected, try getting descriptor directly
  GreetingReplyDescriptor <- RProtoBuf::P("helloworld.GreetingReply")
  if(is.null(GreetingReplyDescriptor)) {
    stop("Could not extract ResponseType descriptor for helloworld.GreetingReply.")
  }
}


# Define SayHello implementation
flog.info("Defining SayHello implementation for method: %s", hello_method_name)
impl[[hello_method_name]]$f <- function(request) {
  # ... (your existing implementation, which should be fine with simple 'request$name') ...
  name_in <- request$name
  flog.info("SERVER: SayHello R callback invoked for name: %s", name_in)
  response_message <- paste('Hello,', name_in)
  RProtoBuf::new(GreetingReplyDescriptor, message = response_message)
}

# Define SayThanks implementation
flog.info("Defining SayThanks implementation for method: %s", thanks_method_name)
impl[[thanks_method_name]]$f <- function(request) {
  name_in <- request$name
  flog.info("SERVER: SayThanks R callback invoked for name: %s", name_in)
  response_message <- paste('Thanks,', name_in)
  RProtoBuf::new(GreetingReplyDescriptor, message = response_message)
}

# Define SayBye implementation
flog.info("Defining SayBye implementation for method: %s", bye_method_name)
impl[[bye_method_name]]$f <- function(request) {
  name_in <- request$name
  flog.info("SERVER: SayBye R callback invoked for name: %s", name_in)
  response_message <- paste('Bye,', name_in)
  RProtoBuf::new(GreetingReplyDescriptor, message = response_message)
}

# --- Start Server ---
server_address <- "0.0.0.0:50051" # Hardcoded for this demo
flog.info("Starting gRPC server on: %s", server_address)

server_hooks <- list(
  server_start = function(params){ flog.info("Server startup hook: Listening on port %s", params$port) },
  stopped = function() { flog.info("Server stopped hook triggered.") },
  exit = function() { flog.info("--- Hello World Server Demo Exiting ---") }
)

tryCatch({
  grpc::start_server(impl, server_address, hooks = server_hooks)
  flog.info("start_server returned (server likely shut down by Ctrl+C or hook).")
}, error = function(e) {
  flog.fatal("Failed to start or run gRPC server: %s", e$message)
  stop("Server failed.")
})

flog.info("--- Hello World Server Demo Script End (Server process may have exited) ---")
