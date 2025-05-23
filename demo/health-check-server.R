#' Health Check Server Demo
#'
#' This demo starts a gRPC server implementing both the Greeter (SayHello)
#' service from helloworld.proto and the standard Health Check service.
#' It writes the dynamically assigned port to a file for the client demo to read.
#' @demo health-check-server
#' @importFrom futile.logger flog.info flog.error flog.warn flog.threshold FATAL
#' @importFrom RProtoBuf P new readProtoFiles
#' @importFrom rpart rpart
#' @importFrom methods is

# --- Setup ---
library(grpc)
library(RProtoBuf)
library(futile.logger)
library(rpart)

flog.threshold(futile.logger::INFO)
flog.info("--- Health Check Server Demo Starting ---")

# --- (Optional) Dummy Model ---
flog.info("Training dummy rpart model (Note: not used by served gRPC methods)...")
iris_data_demo <- iris
names(iris_data_demo) <- tolower(sub('.', '_', names(iris_data_demo), fixed = TRUE))
fit <- rpart::rpart(species ~ ., iris_data_demo)
flog.info("Dummy model training complete.")

# --- Read Service Definitions ---
helloworld_proto_path <- system.file('examples/helloworld.proto', package = 'grpc')
healthcheck_proto_path <- system.file('examples/health_check.proto', package = 'grpc')

if (helloworld_proto_path == "") stop("Could not find helloworld.proto in grpc package examples.")
if (healthcheck_proto_path == "") stop("Could not find health_check.proto in grpc package examples.")

flog.info("Reading service definitions from proto files...")
impl_helloworld <- NULL
impl_health <- NULL
impl <- NULL

tryCatch({
  impl_helloworld <- grpc::read_services(helloworld_proto_path)
  flog.info("Names from helloworld.proto: %s", paste(names(impl_helloworld), collapse=", "))
}, error = function(e) {
  flog.error("Failed to read helloworld.proto: %s", e$message)
  stop("helloworld.proto reading failed.")
})

tryCatch({
  impl_health <- grpc::read_services(healthcheck_proto_path)
  flog.info("Names from health_check.proto: %s", paste(names(impl_health), collapse=", "))
}, error = function(e) {
  flog.error("Failed to read health_check.proto: %s", e$message)
  stop("health_check.proto reading failed.")
})

impl <- c(impl_helloworld, impl_health)
flog.info("Combined 'impl' names: %s", paste(names(impl), collapse=", "))

# --- Define Method Names (SIMPLE NAMES as per logs) ---
# These names MUST match the keys in 'impl' from read_services output
method_say_hello    <- "SayHello"
method_say_thanks   <- "SayThanks"
method_say_bye      <- "SayBye"
method_health_check <- "Check"

# Verify methods exist in the combined 'impl'
required_methods <- c(method_say_hello, method_say_thanks, method_say_bye, method_health_check)
if (!all(required_methods %in% names(impl))) {
  missing_methods <- setdiff(required_methods, names(impl))
  flog.error("Implementation object 'impl' missing expected methods: %s",
             paste(missing_methods, collapse=", "))
  flog.info("Actual names in 'impl': %s", paste(names(impl), collapse=", "))
  stop("Implementation object structure incorrect. Check method names provided by read_services.")
}

# --- Get Response Message Descriptors ---
GreetingReplyDescriptor <- NULL
if(method_say_hello %in% names(impl) && !is.null(impl[[method_say_hello]]$ResponseType$proto)) {
  GreetingReplyDescriptor <- impl[[method_say_hello]]$ResponseType$proto
} else { # Fallback if descriptor not directly in impl structure from read_services
  flog.warn("Could not get GreetingReplyDescriptor from impl for '%s'. Falling back to P().", method_say_hello)
  GreetingReplyDescriptor <- RProtoBuf::P("helloworld.GreetingReply")
}
if(is.null(GreetingReplyDescriptor)) stop("FATAL: Could not get helloworld.GreetingReply descriptor.")

HealthCheckResponseDescriptor <- NULL
if(method_health_check %in% names(impl) && !is.null(impl[[method_health_check]]$ResponseType$proto)) {
  HealthCheckResponseDescriptor <- impl[[method_health_check]]$ResponseType$proto
} else { # Fallback
  flog.warn("Could not get HealthCheckResponseDescriptor from impl for '%s'. Falling back to P().", method_health_check)
  HealthCheckResponseDescriptor <- RProtoBuf::P("grpc.health.v1.HealthCheckResponse")
}
if(is.null(HealthCheckResponseDescriptor)) stop("FATAL: Could not get grpc.health.v1.HealthCheckResponse descriptor.")

# --- Implement Service Methods using SIMPLE names ---
flog.info("Defining SayHello implementation for method: %s", method_say_hello)
impl[[method_say_hello]]$f <- function(request) {
  name_in <- if("name" %in% names(request)) request$name else "Unknown"
  flog.info("HEALTH_SERVER: SayHello R callback invoked for name: %s", name_in)
  RProtoBuf::new(GreetingReplyDescriptor, message = paste('Hello from HealthServer,', name_in))
}

flog.info("Defining Health Check implementation for method: %s", method_health_check)
impl[[method_health_check]]$f <- function(request) {
  service_name_checked <- if("service" %in% names(request)) request$service else ""
  flog.info("HEALTH_SERVER: Health Check R callback invoked for service: '%s'", service_name_checked)
  current_status <- 1 # SERVING
  known_services_simple <- c("SayHello", "SayThanks", "SayBye", "Check") # Based on your impl names
  # For health check, a specific service name might be fully qualified
  known_services_fq_health <- c("", "helloworld.Greeter", "grpc.health.v1.Health")

  if (service_name_checked != "" &&
      !(service_name_checked %in% known_services_simple) &&
      !(service_name_checked %in% known_services_fq_health) ) {
    flog.warn("Health check for unknown/unserved service '%s', returning NOT_SERVING.", service_name_checked)
    current_status <- 2 # NOT_SERVING
  } else {
    flog.info("Service '%s' considered healthy by HealthServer, returning SERVING.", service_name_checked)
  }
  RProtoBuf::new(HealthCheckResponseDescriptor, status = current_status)
}

# Implement SayThanks and SayBye
flog.info("Defining SayThanks implementation for method: %s", method_say_thanks)
impl[[method_say_thanks]]$f <- function(request) {
  name_in <- if("name" %in% names(request)) request$name else "Unknown"
  flog.info("HEALTH_SERVER: SayThanks R callback invoked for name: %s", name_in)
  RProtoBuf::new(GreetingReplyDescriptor, message = paste('Thanks from HealthServer,', name_in))
}

flog.info("Defining SayBye implementation for method: %s", method_say_bye)
impl[[method_say_bye]]$f <- function(request) {
  name_in <- if("name" %in% names(request)) request$name else "Unknown"
  flog.info("HEALTH_SERVER: SayBye R callback invoked for name: %s", name_in)
  RProtoBuf::new(GreetingReplyDescriptor, message = paste('Bye from HealthServer,', name_in))
}

# --- DEFINE port_file and server_hooks BEFORE tryCatch for start_server ---
#port_file <- file.path(dirname(tempdir(check = TRUE)), 'grpc_health_check_server.port')
port_file <- "C:/Users/laurensvdb/grpc_health_check_server.port"
flog.info("HEALTH_SERVER: Port file will be: %s", port_file)

server_hooks <- list(
  run = function(params) {
    if (is.null(params$port) || !is.numeric(params$port) || params$port <= 0) {
      flog.fatal("Invalid port received in run hook: %s. Stopping.", params$port)
      stop("Failed to get valid port from server.")
    }
    flog.info('HEALTH_SERVER: Server running on port %d (from hook)', params$port)
    tryCatch({
      cat(params$port, file = port_file)
      flog.info("HEALTH_SERVER: Port written to: %s", port_file)
    }, error = function(e){
      flog.error("HEALTH_SERVER: Failed to write port file '%s': %s", port_file, e$message)
    })
  },
  stopped = function() {
    flog.info("HEALTH_SERVER: Server stopped hook triggered.")
    if (file.exists(port_file)) { flog.info("HEALTH_SERVER: Removing port file: %s", port_file); file.remove(port_file) }
  },
  exit = function() {
    if (file.exists(port_file)) { flog.warn("HEALTH_SERVER: Exit hook: Removing port file: %s", port_file); file.remove(port_file) }
    flog.info("--- Health Check Server Demo Exiting ---")
  }
)

flog.info("Starting gRPC server (Health Check version)...")
tryCatch({
  grpc::start_server(impl, '0.0.0.0:0', hooks = server_hooks) # Dynamic port
  flog.info("start_server returned (server likely shut down by Ctrl+C or hook).")
}, error = function(e) {
  flog.fatal("Failed to start or run gRPC server: %s", e$message)
  if (file.exists(port_file)) file.remove(port_file) # Now port_file is defined
  stop("Server failed.")
})

flog.info("--- Health Check Server Demo Script End ---")
