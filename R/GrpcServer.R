#' gRPC Server R6 Class
#'
#' @description
#' An R6 class to define, manage, and run a gRPC server. It encapsulates the
#' service implementation, channel details, and lifecycle hooks into a single
#' object.
#'
#' @details
#' The server is configured upon initialization with a service implementation,
#' a channel string, and optional hooks. The `run()` method starts the server,
#' which blocks the R session until it is shut down or the specified duration
#' elapses.
#'
#' Handler functions within the implementation should use the `newResponse()`
#' helper function to construct valid response messages.
#'
#' @seealso \code{\link{newResponse}}, \code{\link{grpc_default_hooks}}
#' @importFrom RProtoBuf P serialize read new
#' @importFrom methods is
#' @export
GrpcServer <- R6::R6Class("GrpcServer",
                          private = list(
                            .impl = NULL,
                            .channel = NULL,
                            .hooks = NULL,
                            .server_handlers = NULL,

                            # This private method processes the user-provided implementation list ('impl')
                            # and prepares the handler functions for the C++ backend. This is equivalent
                            # to the main logic block inside the original start_server function.
                            # (Inside the private list of the R6Class definition)
                            .process_implementation = function() {
                              if (!is.list(private$.impl)) {
                                stop("'impl' must be a list.")
                              }

                              if (is.null(private$.impl) || length(private$.impl) == 0) {
                                private$.server_handlers <- list()
                                return(invisible(self))
                              }

                              server_functions <- lapply(private$.impl, function(fn_spec) {
                                req_desc <- fn_spec[["RequestType"]]
                                res_desc <- fn_spec[["ResponseType"]]
                                r_handler_func <- fn_spec[["f"]]
                                method_full_name <- fn_spec[["name"]]

                                # FIXED: Use paste0 to create error messages without extra spaces
                                if (!is(req_desc, "Descriptor")) {
                                  stop(paste0("Invalid RequestType for method '", method_full_name,
                                              "'. Expected RProtoBuf 'Descriptor'."))
                                }
                                if (!is(res_desc, "Descriptor")) {
                                  stop(paste0("Invalid ResponseType for method '", method_full_name,
                                              "'. Expected RProtoBuf 'Descriptor'."))
                                }
                                if (!is.function(r_handler_func)) {
                                  stop(paste0("Handler 'f' for method ", method_full_name, " is not a function"))
                                }

                                f_with_attrs <- structure(r_handler_func,
                                                          RequestTypeDescriptor  = req_desc,
                                                          ResponseTypeDescriptor = res_desc)

                                function(request_bytes_from_cpp) {
                                  request_msg <- RProtoBuf::read(req_desc, request_bytes_from_cpp)
                                  response_msg <- f_with_attrs(request_msg)
                                  RProtoBuf::serialize(response_msg, NULL)
                                }
                              })

                              names(server_functions) <- vapply(private$.impl, function(x) x$name, character(1), USE.NAMES = FALSE)
                              private$.server_handlers <- server_functions

                              invisible(self)
                            }
                          ),

                          public = list(
                            #' @description
                            #' Create a new `GrpcServer` instance.
                            #' @param impl A named list defining the service implementation. See the
                            #'   documentation for `start_server` for details on the structure.
                            #' @param channel A string specifying the host and port, e.g., `'0.0.0.0:50051'`.
                            #' @param hooks Optional list of hook functions to customize server behavior.
                            #'   Defaults to `grpc_default_hooks()`.
                            initialize = function(impl, channel, hooks = grpc_default_hooks()) {
                              private$.impl <- impl
                              private$.channel <- channel
                              private$.hooks <- hooks
                              private$.process_implementation() # Prepare handlers upon initialization
                            },

                            #' @description
                            #' Start and run the gRPC server. This function blocks the R session.
                            #' @param duration_seconds Numeric duration (in seconds) that the server
                            #'   should run. The server will shut down automatically after this period.
                            #'   If not specified, it may run until interrupted (behavior depends on C++ layer).
                            #' @return Returns `invisible(self)` upon server shutdown, allowing for chaining if needed.
                            run = function(duration_seconds = 30) {

                              if (!is.null(private$.hooks$exit) && is.function(private$.hooks$exit)) {
                                on.exit(private$.hooks$exit())
                              }

                              # Using futile.logger or another logger is assumed.
                              flog.info("R GrpcServer: Calling C++ robust_grpc_server_run...")

                              # Call the C++ backend with the prepared handlers and configuration
                              robust_grpc_server_run(
                                r_service_handlers = private$.server_handlers,
                                r_hoststring = private$.channel,
                                r_hooks = private$.hooks,
                                r_server_duration_seconds = duration_seconds
                              )

                              flog.info("R GrpcServer: robust_grpc_server_run returned.")
                              invisible(self)
                            }
                          )
)


#' Construct a Response Message Object for a gRPC Service Handler
#'
#' This is a helper function designed to be called from within user-defined
#' R functions that handle gRPC service method calls. It uses attributes
#' (specifically `ResponseTypeDescriptor`) attached to the handler function
#' by the `GrpcServer` to automatically determine the correct RProtoBuf message
#' type for the response.
#'
#' @param ... Arguments to be passed to `RProtoBuf::new()` to populate the fields
#'   of the response message. These should match the fields defined in your
#'   `.proto` file for the response message type.
#' @param WFUN (Advanced Usage) The calling R handler function. This defaults to
#'   the parent frame's function (`sys.function(sys.parent())`), which is
#'   typically the user's gRPC service handler function.
#' @return An RProtoBuf message object of the type expected for the response of
#'   the calling gRPC service handler.
#'
#' @importFrom RProtoBuf new
#' @importFrom methods is
#' @export
#' @seealso \code{\link{GrpcServer}}
newResponse <- function(..., WFUN = sys.function(sys.parent())) {
  # WFUN correctly defaults to the function that *called* newResponse.
  # The GrpcServer's internal `.process_implementation` method attaches the
  # descriptor to this function.
  response_descriptor <- attr(WFUN, "ResponseTypeDescriptor")

  if (is.null(response_descriptor)) {
    stop(paste0("newResponse: The calling function (", deparse(substitute(WFUN)),
                ") is missing the 'ResponseTypeDescriptor' attribute. ",
                "This attribute is normally set by 'GrpcServer' on your handler function. ",
                "Ensure you are calling newResponse from within a gRPC handler function."))
  }
  if (!is(response_descriptor, "Descriptor")) {
    stop(paste0("newResponse: The 'ResponseTypeDescriptor' attribute on function '",
                deparse(substitute(WFUN)), "' is not a valid RProtoBuf 'Descriptor' object. ",
                "Current class: ", paste(class(response_descriptor), collapse=", ")))
  }

  RProtoBuf::new(response_descriptor, ...)
}
