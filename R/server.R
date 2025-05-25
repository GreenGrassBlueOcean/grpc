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

#' Construct a Response Message Object for a gRPC Service Handler
#'
#' This is a helper function designed to be called from within user-defined
#' R functions that handle gRPC service method calls. It uses attributes
#' (specifically `ResponseTypeDescriptor`) attached to the handler function
#' by `start_server` to automatically determine the correct RProtoBuf message
#' type for the response.
#'
#' @param ... Arguments to be passed to `RProtoBuf::new()` to populate the fields
#'   of the response message. These should match the fields defined in your
#'   `.proto` file for the response message type.
#' @param WFUN (Advanced Usage) The calling R handler function. This defaults to
#'   the parent frame's function (`sys.function(sys.parent())`), which is
#'   typically the user's gRPC service handler function (e.g., their `SayHello`
#'   implementation) as wrapped by `start_server`. This argument allows
#'   `newResponse` to find the `ResponseTypeDescriptor` attribute. It's
#'   generally not necessary for users to set this argument manually.
#'
#' @return An RProtoBuf message object of the type expected for the response of
#'   the calling gRPC service handler.
#'
#' @importFrom RProtoBuf new
#' @importFrom methods is
#' @export
#' @seealso \code{\link{start_server}}
#' @examples
#' \dontrun{
#' # This function is typically used inside a service handler function.
#' # Assume 'MyResponse' is the RProtoBuf message type for the response,
#' # and 'start_server' has correctly attributed the handler.
#'
#' # Example handler for a service method:
#' my_service_handler <- function(request) {
#'   # ... process request ...
#'   response_message_text <- paste("Responding to:", request$name)
#'
#'   # Use newResponse to create the response message object.
#'   # 'message' here is assumed to be a field in 'MyResponse.proto'.
#'   newResponse(message = response_message_text, other_field = 123)
#' }
#'
#' # The 'impl' structure for start_server would look like:
#' # service_impl <- list(
#' #   MyMethod = list(
#' #     RequestType = P(MyRequest),  # RProtoBuf Descriptor for request
#' #     ResponseType = P(MyResponse), # RProtoBuf Descriptor for response
#' #     f = my_service_handler
#' #   )
#' # )
#' #
#' # When 'my_service_handler' is called by the gRPC server framework (via start_server),
#' # 'newResponse()' will correctly use P(MyResponse) to create the new message.
#' }
newResponse <- function(..., WFUN = sys.function(sys.parent())) {
  # WFUN now correctly defaults to the function that *called* newResponse
  # (which, in the server context, is the f_with_attrs wrapper created in start_server)
  response_descriptor <- attr(WFUN, "ResponseTypeDescriptor")

  if (is.null(response_descriptor)) {
    stop(paste0("newResponse: The calling function (", deparse(substitute(WFUN)),
                ") is missing the 'ResponseTypeDescriptor' attribute. ",
                "This attribute is normally set by 'start_server' on your handler function. ",
                "Ensure you are calling newResponse from within a gRPC handler function ",
                "managed by 'start_server'."))
  }
  if (!is(response_descriptor, "Descriptor")) {
    stop(paste0("newResponse: The 'ResponseTypeDescriptor' attribute on function '",
                deparse(substitute(WFUN)), "' is not a valid RProtoBuf 'Descriptor' object. ",
                "Current class: ", paste(class(response_descriptor), collapse=", ")))
  }

  RProtoBuf::new(response_descriptor, ...)
}
