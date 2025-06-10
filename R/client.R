#' Build a gRPC client stub
#'
#' Creates a list of functions that can be used to call methods on a gRPC service.
#'
#' @param services A list describing the service methods, typically from \code{read_services()}.
#'   Each element corresponds to a gRPC method and should be a list containing:
#'   \itemize{
#'     \item \code{name}: The fully qualified gRPC method string (e.g., "/package.Service/MethodName").
#'     \item \code{RequestTypeName}: Character string: the fully qualified name of the request message type.
#'     \item \code{ResponseTypeName}: Character string: the fully qualified name of the response message type.
#'   }
#' @param channel A string specifying the server address and port (e.g., "localhost:50051").
#' @return A list where names correspond to the simple service method names.
#'   Each element is a list with \code{build(...)} and \code{call(...)} functions.
#'
#' @importFrom RProtoBuf serialize read new P descriptor
#' @importFrom methods is
#' @importFrom futile.logger flog.info flog.debug flog.warn
#' @export
grpc_client <- function(services, channel) {
  if (!is.list(services)) stop("'services' must be a list")
  if (!is.character(channel) || length(channel) != 1 || !nzchar(channel)) stop("'channel' must be non-empty string")

  # Internal logging helpers (.can_flog, .log_info, etc.) should be defined in R/utils-logging.R

  client_stubs <- lapply(names(services), function(simple_method_name) {
    method_spec <- services[[simple_method_name]]

    # Expecting Descriptors now, as per original working version
    if (!is.list(method_spec) || is.null(method_spec$RequestType) || is.null(method_spec$ResponseType) ||
        is.null(method_spec$name) || !is.character(method_spec$name) || !nzchar(method_spec$name)) {
      stop(paste("Spec for method '", simple_method_name, "' invalid (name, RequestType, ResponseType)."))
    }

    req_descriptor <- method_spec$RequestType
    res_descriptor <- method_spec$ResponseType
    full_method_path <- method_spec$name

    # Also get the FQN string for class checking if available (from new read_services)
    # Fallback to RProtoBuf::name(descriptor) if *TypeName not present (for backward compat with old read_services output)
    req_type_fqn_str <- method_spec$RequestTypeName %||% RProtoBuf::name(req_descriptor)
    # res_type_fqn_str <- method_spec$ResponseTypeName %||% RProtoBuf::name(res_descriptor) # For response class check if needed

    if (!is(req_descriptor, "Descriptor")) stop(paste("Invalid RequestType for", simple_method_name))
    if (!is(res_descriptor, "Descriptor")) stop(paste("Invalid ResponseType for", simple_method_name))

    list(
      build = function(...) {
        # .log_info("grpc_client$build: Using descriptor (RProtoBuf::name: '%s') for RProtoBuf::new()", RProtoBuf::name(req_descriptor))
        msg <- RProtoBuf::new(req_descriptor, ...) # Use descriptor
        # .log_info("grpc_client$build: Created message of class: %s", paste(class(msg), collapse=", "))
        return(msg)
      },
      call = function(request_message, metadata = list()) {
        # Class check:
        # 1. Is it a Message?
        # 2. Does its internal descriptor match the expected req_descriptor? (original strict check)
        # OR, if we want to use the FQN string for a more flexible check:
        # Is the FQN of the request type part of the request_message's class vector?
        if (!is(request_message, "Message")) {
          stop(paste0("Arg 'request_message' for '", simple_method_name, "' not an RProtoBuf Message."))
        }
        # Original strict check (good if RProtoBuf::new(Descriptor) consistently sets classes):
        if (!identical(RProtoBuf::descriptor(request_message), req_descriptor)) {
          # Fallback/alternative check using FQN string if available
          if (!(req_type_fqn_str %in% class(request_message))) {
            stop(paste0("Arg 'request_message' for '", simple_method_name,
                        "' not expected type. Expected type related to '", req_type_fqn_str,
                        " (desc name: ", RProtoBuf::name(req_descriptor), ")",
                        ". Actual class: ", paste(class(request_message), collapse=", "),
                        ". Use '$build()' to create it."))
          }
        }

        serialized_request <- RProtoBuf::serialize(request_message, NULL)
        serialized_response <- robust_grpc_client_call(
          r_target_str = channel, r_method_str = full_method_path,
          r_request_payload = serialized_request, r_metadata_sexp = metadata
        )

        response_obj <- NULL
        if (is.null(serialized_response)) {
          .log_warn("NULL response payload for '%s'. Returning empty %s.",
                    simple_method_name, RProtoBuf::name(res_descriptor))
          response_obj <- RProtoBuf::new(res_descriptor)
        } else if (length(serialized_response) == 0) {
          .log_debug("Empty response payload for '%s'. Interpreting as empty %s.",
                     simple_method_name, RProtoBuf::name(res_descriptor))
          response_obj <- RProtoBuf::new(res_descriptor)
        } else {
          response_obj <- RProtoBuf::read(res_descriptor, serialized_response)
        }
        # .log_info("grpc_client$call: Deserialized response to class: %s", paste(class(response_obj), collapse=", "))
        return(response_obj)
      }
    )
  })
  names(client_stubs) <- names(services)
  return(client_stubs)
}


#' Default Value for NULL
#'
#' This infix operator returns the right-hand side \code{y} if the
#' left-hand side \code{x} is \code{NULL}; otherwise, it returns \code{x}.
#'
#' @param x The value to test.
#' @param y The default value to return if \code{x} is \code{NULL}.
#' @return \code{x} if it is not \code{NULL}, otherwise \code{y}.
#' @examples
#' NULL %||% 5 # Returns 5
#' 10 %||% 5   # Returns 10
#'
#' my_var <- NULL
#' value <- my_var %||% "default_string"
#' print(value) # "default_string"
#'
#' my_var2 <- list(a = 1)
#' value2 <- my_var2 %||% list()
#' print(value2) # list(a = 1)
`%||%` <- function (x, y) {
  if (is.null(x)) y else x
}
