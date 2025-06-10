#' gRPC Client R6 Class
#'
#' @description
#' An R6 class to create and manage a gRPC client. It parses a `.proto` file
#' to generate callable stubs for all RPC methods defined in the service.
#'
#' @details
#' The client is configured upon initialization with the path to a `.proto` file
#' and the server's channel string (address and port). It internally uses a
#' `ProtoParser` to compile the proto and discover service methods.
#'
#' Once created, the client's stubs are immediately available in the public
#' `$stubs` field. Each stub provides a `$build()` method to construct a valid
#' request message and a `$call()` method to execute the RPC.
#'
#' @export
#' @seealso \code{\link{ProtoParser}}, \code{\link{GrpcLogger}}
#' @examples
#' \dontrun{
#' # Helper function to create a temporary .proto file for the example
#' create_temp_proto <- function(content) {
#'   proto_file <- tempfile(fileext = ".proto")
#'   writeLines(text = content, con = proto_file)
#'   return(proto_file)
#' }
#'
#' # 1. Define proto content
#' proto_content <- '
#' syntax = "proto3";
#' package helloworld;
#' message HelloRequest { string name = 1; }
#' message HelloReply { string message = 1; }
#' service Greeter { rpc SayHello (HelloRequest) returns (HelloReply); }
#' '
#' proto_file <- create_temp_proto(proto_content)
#'
#' # 2. Create a gRPC client instance
#' # This automatically parses the file and prepares the stubs.
#' # NOTE: This example assumes a gRPC server is running on localhost:50051
#' client <- GrpcClient$new(proto_file, "localhost:50051")
#'
#' # 3. Access the stubs and build a request message
#' request <- client$stubs$SayHello$build(name = "R6")
#' print(request)
#'
#' # 4. Call the remote method with the request message
#' # The C++ backend function `robust_grpc_client_call` needs to be available
#' # For this example to run, we would mock it.
#' # response <- client$stubs$SayHello$call(request)
#' # print(response$message)
#'
#' # Clean up the temporary file
#' unlink(proto_file)
#' }
# In your GrpcClient.R file
GrpcClient <- R6::R6Class("GrpcClient",
                          private = list(
                            .parser = NULL,
                            .channel = NULL,
                            .logger = NULL,

                            .generate_stubs = function() {
                              # ... (This method's internal logic remains the same)
                              private$.logger$info("Generating gRPC client stubs...")
                              private$.parser$compile()$parse()
                              services <- private$.parser$get_services()
                              # ... (rest of the method is unchanged)
                              if (length(services) == 0) {
                                private$.logger$warn("No services found in the provided proto file.")
                                return(list())
                              }
                              stubs <- lapply(names(services), function(simple_method_name) {
                                method_spec <- services[[simple_method_name]]
                                req_descriptor <- method_spec$RequestType
                                res_descriptor <- method_spec$ResponseType
                                full_method_path <- method_spec$name
                                req_type_fqn_str <- method_spec$RequestTypeName
                                list(
                                  build = function(...) {
                                    private$.logger$debug("Client stub '%s': building request message.", simple_method_name)
                                    RProtoBuf::new(req_descriptor, ...)
                                  },
                                  call = function(request_message, metadata = list()) {
                                    if (!is(request_message, "Message")) {
                                      stop(paste0("Argument 'request_message' for '", simple_method_name,
                                                  "' is not an RProtoBuf Message. Use the $build() method to create one."),
                                           call. = FALSE)
                                    }
                                    if (!identical(RProtoBuf::descriptor(request_message), req_descriptor)) {
                                      if (!(req_type_fqn_str %in% class(request_message))) {
                                        stop(paste0("Argument 'request_message' for '", simple_method_name,
                                                    "' is not the expected type. Expected a message of type '", req_type_fqn_str,
                                                    "'. Actual class: ", paste(class(request_message), collapse=", ")),
                                             call. = FALSE)
                                      }
                                    }
                                    private$.logger$info("Client stub '%s': calling remote method.", simple_method_name)
                                    serialized_request <- RProtoBuf::serialize(request_message, NULL)
                                    serialized_response <- robust_grpc_client_call(
                                      r_target_str = private$.channel,
                                      r_method_str = full_method_path,
                                      r_request_payload = serialized_request,
                                      r_metadata_sexp = metadata
                                    )
                                    if (is.null(serialized_response)) {
                                      private$.logger$warn("NULL response payload for '%s'. Returning empty response.",
                                                           simple_method_name)
                                      return(RProtoBuf::new(res_descriptor))
                                    } else if (length(serialized_response) == 0) {
                                      private$.logger$debug("Empty response payload for '%s'. Interpreting as empty response.",
                                                            simple_method_name)
                                      return(RProtoBuf::new(res_descriptor))
                                    } else {
                                      private$.logger$debug("Deserializing response for '%s'.", simple_method_name)
                                      return(RProtoBuf::read(res_descriptor, serialized_response))
                                    }
                                  }
                                )
                              })
                              names(stubs) <- names(services)
                              private$.logger$info("Successfully generated %d client stubs.", length(stubs))
                              return(stubs)
                            }
                          ),

                          public = list(
                            stubs = NULL,

                            #' @description
                            #' Create a new `GrpcClient` instance.
                            #' @param parser A fully instantiated `ProtoParser` object.
                            #' @param channel A string specifying the server address and port (e.g., "localhost:50051").
                            #' @param logger An optional logger object. If `NULL`, a default `GrpcLogger` is used.
                            initialize = function(parser, channel, logger = NULL) {
                              private$.logger <- logger %||% GrpcLogger$new()

                              if (!is.character(channel) || length(channel) != 1 || !nzchar(channel)) {
                                stop("'channel' must be a non-empty string.", call. = FALSE)
                              }
                              private$.channel <- channel

                              # The KEY CHANGE: Accept the parser, don't create it.
                              if (!R6::is.R6(parser) || !inherits(parser, "ProtoParser")) {
                                stop("'parser' must be an R6 object inheriting from ProtoParser.", call. = FALSE)
                              }
                              private$.parser <- parser

                              self$stubs <- private$.generate_stubs()
                              self$lock()
                            },

                            lock = function() {
                              lockBinding("stubs", self)
                            }
                          )
)
