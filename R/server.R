#' Start and Run a gRPC Server
#'
#' Starts and runs a gRPC server, listening on the specified channel and
#' dispatching requests to the appropriate R functions in the implementation.
#' This function typically blocks the R session while the server is running.
#'
#' @param impl A named list defining the service implementation. Each element
#'   should correspond to a gRPC service method. The *name* of the element
#'   should be the method name (e.g., `'SayHello'`). The *value* should be a
#'   list containing: `RequestType` (the `RProtoBuf` message descriptor for
#'   the request, e.g., `P(MyRequest)`), `ResponseType` (the `RProtoBuf`
#'   message descriptor for the response, e.g., `P(MyResponse)`), and `f`
#'   (an R function that takes the request message object as input and returns
#'   the response message object).
#' @param channel A string specifying the host and port for the server to bind
#'   to, in the format `'host:port'` (e.g., `'0.0.0.0:50051'` to listen on all
#'   interfaces, or `'localhost:50051'`).
#' @param hooks Optional list of hook functions to customize server behavior
#'   (see Details or `@seealso grpc_default_hooks`). Defaults to `grpc_default_hooks()`.
#'   Supported hooks: `server_create`, `queue_create`, `bind` (params$port is available),
#'   `server_start`, `run`, `shutdown`, `stopped`, `exit`.
#' @param duration_seconds numeric duration that the server should be running defaults to 30 seconds
#' @return This function is called for its side effects and normally blocks R
#'   indefinitely. Returns `NULL` invisibly if the server shuts down (e.g., via Ctrl+C
#'   or a shutdown hook).
#' @importFrom RProtoBuf P serialize read new
#' @export
#' @seealso \code{\link{grpc_default_hooks}}, \code{\link{grpc_client}}
#' @examples
#' \dontrun{
#' # Conceptual example - requires actual ProtoBuf message types
#' # Assume MyRequest and MyResponse are RProtoBuf message types loaded via readProtoFiles()
#'
#' say_hello_impl <- function(request) {
#'   message <- paste("Hello,", request$name)
#'   # Assumes newResponse() helper exists and works based on this context
#'   newResponse(message = message, WFUN = sys.function())
#' }
#'
#' service_impl <- list(
#'   SayHello = list(
#'     RequestType = P(MyRequest),
#'     ResponseType = P(MyResponse),
#'     f = say_hello_impl
#'   )
#' )
#' }
# In R/server.R
start_server <- function(impl, channel, hooks = grpc_default_hooks(), duration_seconds = 30) {

  if (!is.null(hooks$exit) && is.function(hooks$exit)) {
    on.exit(hooks$exit())
  }

  if (!is.list(impl)) {
    stop("'impl' must be a list.")
  }

  if (!is.null(impl) && length(impl) > 0) {
    server_functions <- lapply(impl, function(fn_spec) {
      # fn_spec should now be like:
      # list(RequestType = <MessageDescriptor>, ResponseType = <MessageDescriptor>, f = some_r_func, name = "/pkg.Svc/Mtd")

      req_desc <- fn_spec[["RequestType"]]       # Get the descriptor directly
      res_desc <- fn_spec[["ResponseType"]]     # Get the descriptor directly
      r_handler_func <- fn_spec[["f"]]
      method_full_name <- fn_spec[["name"]] # Get the full name for error messages

      # Check if they are actual descriptors
      if (!is(req_desc, "Descriptor")) {
        stop(paste("Invalid RequestType for method '", method_full_name,
                   "'. Expected class 'Descriptor', got '", paste(class(req_desc), collapse=", "), "'", sep=""))
      }
      if (!is(res_desc, "Descriptor")) {
        stop(paste("Invalid ResponseType for method '", method_full_name,
                   "'. Expected class 'Descriptor', got '", paste(class(res_desc), collapse=", "), "'", sep=""))
      }
      if (!is.function(r_handler_func)) {
        stop(paste("Handler 'f' for method", method_full_name, "is not a function"))
      }

      f_with_attrs <- structure(r_handler_func,
                                RequestTypeDescriptor  = req_desc,
                                ResponseTypeDescriptor = res_desc
      )

      function(request_bytes_from_cpp) {
        request_msg <- RProtoBuf::read(req_desc, request_bytes_from_cpp)
        response_msg <- f_with_attrs(request_msg)
        RProtoBuf::serialize(response_msg, NULL)
      }
    })
    # Key 'server_functions' by the *fully qualified gRPC method path*
    names(server_functions) <- vapply(impl, function(x) x$name, character(1), USE.NAMES = FALSE)
  } else {
    server_functions <- list()
  }

  flog.info("R start_server: Calling C++ robust_grpc_server_run with R handlers and hooks (though C++ may not use them fully yet).")

  # This is where you'd pass server_functions and hooks to the C++ side
  # once robust_grpc_server_run is updated to accept them.
  # For now, to match its current C++ signature:
  # robust_grpc_server_run(channel, duration_seconds)
  # OR, if you've started updating robust_grpc_server_run's signature:
  robust_grpc_server_run(
    r_service_handlers = server_functions,
    r_hoststring = channel,
    r_hooks = hooks,
    r_server_duration_seconds = duration_seconds
  )


  flog.info("R start_server: robust_grpc_server_run returned.")
  invisible(NULL)
}

# Your newResponse function (ensure it's also in an R file in your package, e.g., R/utils.R or R/server.R)
#' @importFrom methods is
#' @export
newResponse <- function(..., WFUN = sys.function(sys.parent())) { # Corrected default
  # WFUN now correctly defaults to the function that *called* newResponse
  response_descriptor <- attr(WFUN, "ResponseTypeDescriptor")
  if (is.null(response_descriptor) || !is(response_descriptor, "Descriptor")) {
    stop(paste0("newResponse: Calling function WFUN (", deparse(substitute(WFUN)),") is missing a valid ResponseTypeDescriptor attribute, or it's not a 'Descriptor' object."))
  }
  RProtoBuf::new(response_descriptor, ...)
}

# Your grpc_default_hooks function (if not defined elsewhere)
#' @export
grpc_default_hooks <- function() {
  list()
}

# start_server <- function(impl, channel, hooks = grpc_default_hooks(), duration_seconds = 30) {
#
#   if (!is.null(hooks$exit) && is.function(hooks$exit)) {
#     on.exit(hooks$exit())
#   }
#
#   # This section prepares server_functions. It's not used by the current C++ server,
#   # but let's make it syntactically correct.
#   if (!is.null(impl) && length(impl) > 0) {
#     server_functions <- lapply(impl, function(fn_spec) {
#       # fn_spec is something like:
#       # list(RequestType = P("pkg.Msg1"), ResponseType = P("pkg.Msg2"), f = some_r_func)
#
#       req_desc <- fn_spec[["RequestType"]]
#       res_desc <- fn_spec[["ResponseType"]]
#       r_handler_func <- fn_spec[["f"]]
#
#       if (!is(req_desc, "Descriptor")) { # Use is() and check for "Descriptor"
#         stop(paste("Invalid RequestType. Expected class 'Descriptor', got '", paste(class(req_desc), collapse=", "), "'", sep=""))
#       }
#       if (!is(res_desc, "Descriptor")) { # Use is() and check for "Descriptor"
#         stop(paste("Invalid ResponseType. Expected class 'Descriptor', got '", paste(class(res_desc), collapse=", "), "'", sep=""))
#       }
#       if (!is.function(r_handler_func)) stop("Handler 'f' is not a function")
#
#       # Store descriptors as attributes of the handler function 'f'
#       # This is a common pattern for the R handler to know its types.
#       f_with_attrs <- structure(r_handler_func,
#                                 RequestType  = req_desc,
#                                 ResponseType = res_desc)
#
#       # This closure is what C++ would invoke if it were calling R handlers.
#       # It handles serialization/deserialization.
#       function(request_bytes_from_cpp) {
#         request_msg <- RProtoBuf::read(req_desc, request_bytes_from_cpp)
#         response_msg <- f_with_attrs(request_msg) # Call the user's R function
#         RProtoBuf::serialize(response_msg, NULL)
#       }
#     })
#     names(server_functions) <- names(impl) # Use simple names like "SayHello"
#   } else {
#     server_functions <- list()
#   }
#
#   flog.info("R start_server: Calling C++ robust_grpc_server_run for %d seconds on channel %s",
#             duration_seconds, channel)
#
#   robust_grpc_server_run(channel, duration_seconds) # C++ server doesn't use server_functions or hooks yet
#
#   flog.info("R start_server: robust_grpc_server_run returned.")
#   invisible(NULL)
# }
# start_server <- function(impl, channel, hooks = grpc_default_hooks()) {
#
#   if (!is.null(hooks$exit) & is.function(hooks$exit)) {
#     on.exit(hooks$exit())
#   }
#
#   server_functions <- lapply(impl, function(fn){
#     descriptor <- P(fn[["RequestType"]]$proto)
#
#     f <- structure(fn$f,
#                    RequestType  = fn[["RequestType"]],
#                    ResponseType = fn[["ResponseType"]])
#
#     function(x) serialize(f(read(descriptor, x)), NULL)
#   })
#
#   names(server_functions) <- vapply(impl, function(x)x$name, NA_character_)
#
#   #run(server_functions, channel, hooks)
#   robust_grpc_server_run(channel, 30) # Or some other duration
#   invisible(NULL)
# }


#' Construct a new ProtoBuf of ResponseType
#'
#' @param ... threaded through to the ProtoBuf constructor
#' @param WFUN A GRPC service method with RequestType and ResponseType attributes
#' @return Called for side effects (starts the server). Returns `NULL` invisibly.
#'
#' @export
#' @importFrom RProtoBuf P new
newResponse <- function(..., WFUN=sys.function(-1)){
  new(P(attr(WFUN, "ResponseType")$proto), ...)
}
