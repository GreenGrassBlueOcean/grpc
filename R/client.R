#' Build a gRPC client stub
#'
#' Creates a list of functions that can be used to call methods on a gRPC service.
#'
#' @param services A list describing the service methods. Typically generated by
#'   a function like \code{read_services()}. Each element of the list should
#'   correspond to a gRPC method. The name of the list element should be the
#'   simple method name (e.g., "SayHello"). Each element itself should be a list
#'   containing:
#'   \itemize{
#'     \item \code{name}: The fully qualified gRPC method string (e.g., "/package.Service/MethodName").
#'     \item \code{RequestType}: The \code{RProtoBuf::Descriptor} object for the request message type.
#'     \item \code{ResponseType}: The \code{RProtoBuf::Descriptor} object for the response message type.
#'   }
#' @param channel A string specifying the server address and port (e.g., "localhost:50051").
#' @return A list where names correspond to the simple service method names.
#'   Each element is itself a list with two functions:
#'   \itemize{
#'     \item \code{build(...)}: A function to construct a new request message object of the
#'           correct type for that method. Arguments are passed to \code{RProtoBuf::new()}.
#'     \item \code{call(request_message, metadata = list())}: A function to execute the RPC.
#'           It takes the RProtoBuf request message object and an optional named R list for metadata.
#'           It returns the deserialized RProtoBuf response message object.
#'   }
#' @importFrom RProtoBuf serialize read new P
#' @importFrom methods is
#' @export
grpc_client <- function(services, channel) {
  if (!is.list(services)) {
    stop("'services' must be a list (e.g., from read_services).")
  }
  if (!is.character(channel) || length(channel) != 1 || !nzchar(channel)) {
    stop("'channel' must be a non-empty single string (e.g., 'localhost:50051').")
  }

  client_stubs <- lapply(names(services), function(simple_method_name) {
    method_spec <- services[[simple_method_name]]

    # Validate the method specification structure
    if (!is.list(method_spec) ||
        is.null(method_spec$RequestType) ||
        is.null(method_spec$ResponseType) ||
        is.null(method_spec$name) || !is.character(method_spec$name) || !nzchar(method_spec$name)) {
      stop(paste("Service specification for method '", simple_method_name, "' is invalid or missing fields (name, RequestType, ResponseType)."))
    }

    req_descriptor <- method_spec$RequestType
    res_descriptor <- method_spec$ResponseType
    full_method_path <- method_spec$name

    # Validate descriptors
    if (!is(req_descriptor, "Descriptor")) {
      stop(paste("Invalid RequestType for method '", simple_method_name, "'. Expected RProtoBuf 'Descriptor' object."))
    }
    if (!is(res_descriptor, "Descriptor")) {
      stop(paste("Invalid ResponseType for method '", simple_method_name, "'. Expected RProtoBuf 'Descriptor' object."))
    }

    list(
      build = function(...) {
        # Creates an RProtoBuf message object for the request
        RProtoBuf::new(req_descriptor, ...)
      },
      call = function(request_message, metadata = list()) {
        if (!is(request_message, "Message") || !identical(RProtoBuf::descriptor(request_message), req_descriptor)) {
          stop(paste0("Argument 'request_message' for method '", simple_method_name,
                      "' is not a valid RProtoBuf Message of the expected type (",
                      RProtoBuf::name(req_descriptor), "). Use the '$build()' function to create it."))
        }

        serialized_request <- RProtoBuf::serialize(request_message, NULL)

        # Call the C++ function (ensure it's robust_grpc_client_call or its RcppExport wrapper)
        # The Rcpp wrapper robust_grpc_client_call handles the SEXP r_metadata_sexp.
        serialized_response <- robust_grpc_client_call(
          r_target_str = channel,
          r_method_str = full_method_path,
          r_request_payload = serialized_request,
          r_metadata = metadata # Pass the R list directly; C++ expects SEXP or Rcpp::List
        )

        if (is.null(serialized_response)) {
          # This case should ideally be handled by robust_grpc_client_call throwing an error
          # if the RPC truly failed at the C++ level (e.g., connection error, non-OK status).
          # If it can return NULL for a "successful" RPC with an empty body (rare for unary),
          # then create an empty response message.
          flog.warn("Received NULL response payload for method '%s'. Returning empty response message.", simple_method_name)
          return(RProtoBuf::new(res_descriptor))
        }
        if (length(serialized_response) == 0) {
          flog.debug("Received empty (zero-length) response payload for method '%s'. Interpreting as empty message.", simple_method_name)
          return(RProtoBuf::new(res_descriptor)) # Create an empty message of the expected type
        }

        # Deserialize the response
        RProtoBuf::read(res_descriptor, serialized_response)
      }
    )
  })

  names(client_stubs) <- names(services) # Set the names of the stubs to simple method names
  return(client_stubs)
}


# #' Build a client handle (Revised)
# #'
# #' Creates a list of functions that can be used to call methods on a gRPC service.
# #'
# #' @param services A list describing the service implementation. Typically generated
# #'   by \code{grpc::read_services()}. Each element corresponds to a service method.
# #'   The *name* of the element is the simple method name (e.g., "SayHello").
# #'   The *value* is a list containing:
# #'   \code{name} (the fully qualified gRPC method string, e.g., "/package.Service/MethodName"),
# #'   \code{RequestType} (the \code{RProtoBuf} MessageDescriptor for the request),
# #'   \code{ResponseType} (the \code{RProtoBuf} MessageDescriptor for the response).
# #' @param channel A string specifying the server address and port (e.g., "localhost:50051").
# #' @return A list where names correspond to service methods (simple names). Each element
# #'   is a list containing:
# #'   \itemize{
# #'     \item \code{call}: A function to execute the RPC. It takes the request message
# #'           object and an optional metadata character vector (key1, val1, key2, val2, ...).
# #'           It returns the deserialized response message object.
# #'     \item \code{build}: A function to create a new request message object of the
# #'           correct type. It takes arguments to be passed to \code{RProtoBuf::new()}.
# #'   }
# #' @useDynLib grpc, .registration = TRUE
# #' @importFrom RProtoBuf P serialize read new
# #' @importFrom methods is
# #' @export
# grpc_client <- function(services, channel) { # Changed 'impl' to 'services' for clarity
#
#   if (!is.list(services)) stop("'services' must be a list.")
#   if (!is.character(channel) || length(channel) != 1) stop("'channel' must be a single string.")
#
#   client_functions <- lapply(names(services), function(method_simple_name) {
#     fn_spec <- services[[method_simple_name]]
#
#     # Ensure fn_spec has the required components
#     if (!is.list(fn_spec) ||
#         is.null(fn_spec$RequestType) ||
#         is.null(fn_spec$ResponseType) ||
#         is.null(fn_spec$name) || !is.character(fn_spec$name) ) {
#       stop(paste("Service specification for method", method_simple_name, "is invalid."))
#     }
#
#     request_descriptor <- fn_spec$RequestType
#     response_descriptor <- fn_spec$ResponseType
#     fully_qualified_method_name <- fn_spec$name # e.g., "/helloworld.Greeter/SayHello"
#
#     # Validate descriptors
#     if (!is(request_descriptor, "Descriptor")) { # Use "Descriptor" based on our findings
#       stop(paste("Invalid RequestType for method", method_simple_name,
#                  ". Expected class 'Descriptor', got '", paste(class(request_descriptor), collapse=", "), "'", sep=""))
#     }
#     if (!is(response_descriptor, "Descriptor")) { # Use "Descriptor"
#       stop(paste("Invalid ResponseType for method", method_simple_name,
#                  ". Expected class 'Descriptor', got '", paste(class(response_descriptor), collapse=", "), "'", sep=""))
#     }
#
#
#     list(
#       call = function(request_message, metadata = list()) { # metadata as R list
#         if (!is(request_message, "Message")) { # Check if it's an RProtoBuf Message
#           stop("The 'request_message' argument to call() must be an RProtoBuf Message object.")
#         }
#         serialized_request <- RProtoBuf::serialize(request_message, NULL)
#
#         # Convert R list metadata to character vector if needed by C++
#         # robust_grpc_client_call expects Rcpp::List r_metadata, which can take a named R list.
#         # If r_metadata = list("key1", "val1", "key2", "val2"), it's fine.
#         # If it's list(key1="val1", key2="val2"), Rcpp handles it.
#         # If metadata arg is character(0), pass an empty list to C++.
#         cpp_metadata_arg <- if (length(metadata) == 0) list() else metadata
#
#         # Call the C++ function robust_grpc_client_call
#         # This is the R wrapper generated by Rcpp which calls your C++ function.
#         serialized_response <- robust_grpc_client_call(
#           r_target_str = channel,
#           r_method_str = fully_qualified_method_name,
#           r_request_payload = serialized_request,
#           r_metadata_sexp = cpp_metadata_arg
#         )
#
#         if (is.null(serialized_response) || length(serialized_response) == 0) {
#           # Handle cases where server might send an empty response for a successful call,
#           # or if an error occurred that robust_grpc_client_call didn't throw but returned NULL.
#           # For now, let's assume an empty payload means we should try to create an empty response message.
#           # Or, robust_grpc_client_call should throw an error if the RPC truly failed.
#           warning(paste("Received NULL or empty response payload for method", method_simple_name, "- returning empty response message."))
#           return(RProtoBuf::new(response_descriptor)) # Return an empty message of the expected type
#         }
#
#         # Deserialize the response
#         RProtoBuf::read(response_descriptor, serialized_response)
#       },
#       build = function(...) {
#         RProtoBuf::new(request_descriptor, ...)
#       }
#     )
#   })
#
#   names(client_functions) <- names(services) # Ensure names are preserved
#   return(client_functions)
# }






# #' Build a client handle
# #'
# #' Creates a list of functions that can be used to call methods on a gRPC service.
# #'
# #' @param impl A list describing the service implementation. Each element should be
# #'   a list containing details about a service method, including its name (e.g., "SayHello"),
# #'   RequestType, and ResponseType (e.g., P(MyRequestProto), P(MyResponseProto)).
# #' @param channel A string specifying the server address and port (e.g., "localhost:50051").
# #' @return A list where names correspond to service methods. Each element is a list
# #'   containing a `call` function (to execute the RPC) and a `build` function
# #'   (a helper to create request proto messages).
# #' @importFrom RProtoBuf P serialize read new
# #' @importFrom Rcpp sourceCpp evalCpp
# #'
# #' @useDynLib grpc
# #' @import Rcpp
# #' @export
# grpc_client <- function(impl, channel) {
#
#
#   client_functions <- lapply(impl, function(fn)
#     {
#       RequestDescriptor <- P(fn[["RequestType"]]$proto)
#       ResponseDescriptor <- P(fn[["ResponseType"]]$proto)
#
#       list(
#         call = function(x, metadata=character(0)) read(ResponseDescriptor, fetch(channel, fn$name, serialize(x, NULL), metadata)),
#         build = function(...) new(RequestDescriptor, ...)
#       )
#     })
#
#
#
#   client_functions
# }

#, .registration = TRUE
