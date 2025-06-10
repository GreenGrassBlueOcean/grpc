#' Default Value for NULL
#'
#' @description
#' This operator returns the right-hand side of the expression if the left-hand
#' side is `NULL`. It is a convenient shorthand for `if (is.null(x)) y else x`.
#'
#' This operator is often called the "null coalescing" or "null default" operator.
#'
#' @param a The object to test for `NULL`.
#' @param b The default value to return if `a` is `NULL`.
#'
#' @return Returns `a` if it is not `NULL`, otherwise returns `b`.
#'
#' @export
#' @name %||%
#'
#' @examples
#' # Basic usage
#' x <- NULL
#' y <- 42
#'
#' x %||% "default" # Returns "default"
#' y %||% "default" # Returns 42
#'
#' # Common use case in a function
#' configure_settings <- function(settings = NULL) {
#'   default_settings <- list(theme = "dark", notifications = TRUE)
#'   final_settings <- settings %||% default_settings
#'   return(final_settings)
#' }
#'
#' # No settings provided, so defaults are used
#' configure_settings()
#'
#' # User provides custom settings
#' configure_settings(list(theme = "light"))
`%||%` <- function(a, b) {
  if (is.null(a)) {
    b
  } else {
    a
  }
}


#' @title ProtoParser Class for gRPC Services
#'
#' @description
#' An R6 class to parse `.proto` files, compile them using \code{RProtoBuf},
#' and extract gRPC service definitions.
#'
#' @details
#' This class provides a two-step process for handling `.proto` files. First,
#' the `$compile()` method invokes `RProtoBuf` to load the protocol buffer
#' message definitions into the R session. This makes message descriptors
#' available. Second, the `$parse()` method reads the text of the same `.proto`
#' file to identify `service` and `rpc` definitions, linking them to the
#' compiled message descriptors.
#'
#' This two-step approach is necessary because `RProtoBuf` compiles and loads
#' message types but does not expose service definitions in an easily
#' accessible R structure. This parser bridges that gap.
#'
#' @export
#' @examples
#' \dontrun{
#' # Helper function to create a temporary .proto file for the example
#' create_temp_proto <- function(content) {
#'   proto_file <- tempfile(fileext = ".proto")
#'   writeLines(text = content, con = proto_file)
#'   return(proto_file)
#' }
#'
#' # 1. Define proto content with a package, service, and an RPC
#' proto_content <- '
#' syntax = "proto3";
#'
#' package helloworld;
#'
#' message HelloRequest {
#'   string name = 1;
#' }
#'
#' message HelloReply {
#'   string message = 1;
#' }
#'
#' service Greeter {
#'   rpc SayHello (HelloRequest) returns (HelloReply);
#' }
#' '
#'
#' proto_file <- create_temp_proto(proto_content)
#'
#' # 2. Create a new parser instance
#' # This only checks for file existence
#' parser <- ProtoParser$new(proto_file)
#'
#' # 3. Compile the proto file and then parse it
#' # Method chaining is supported
#' parser$compile()$parse()
#'
#' # 4. Retrieve the parsed service definitions
#' services <- parser$get_services()
#'
#' # 5. Inspect the result
#' print(services)
#'
#' # Expected output structure:
#' # $SayHello
#' # $SayHello$name
#' # [1] "/helloworld.Greeter/SayHello"
#' #
#' # $SayHello$RequestType
#' # RProtoBuf Descriptor for message helloworld.HelloRequest
#' #
#' # $SayHello$ResponseType
#' # RProtoBuf Descriptor for message helloworld.HelloReply
#' # ... and other fields
#'
#' # Clean up the temporary file
#' unlink(proto_file)
#' }
ProtoParser <- R6::R6Class("ProtoParser",
                           private = list(
                             file_path = NULL,
                             tokens = NULL,
                             current_token_idx = 1,
                             pkg_name = "",
                             parsed_services = list(),
                             logger = NULL,
                             is_compiled = FALSE,

                             # --- Private Methods (not documented for users) ---
                             .consume_token = function() {
                               if (private$current_token_idx > length(private$tokens)) return(NULL)
                               token <- private$tokens[private$current_token_idx]
                               private$current_token_idx <- private$current_token_idx + 1
                               return(token)
                             },
                             .peek_token = function(offset = 0) {
                               idx <- private$current_token_idx + offset
                               if (idx > 0 && idx <= length(private$tokens)) return(private$tokens[idx])
                               return(NULL)
                             },
                             .expect_token = function(expected_token, error_msg_prefix = "") {
                               token <- private$.consume_token()
                               if (is.null(token) || token != expected_token) {
                                 actual_token_msg <- if (is.null(token)) "EOF" else paste0("'", token, "'")
                                 stop(sprintf("%sExpected '%s', got %s.", error_msg_prefix, expected_token, actual_token_msg), call. = FALSE)
                               }
                               return(token)
                             },
                             .doRPC = function(service_name_arg) {
                               rpc_name_simple <- private$.consume_token()
                               fn <- list(f = I, client_streaming = FALSE, server_streaming = FALSE)
                               private$.expect_token("(", sprintf("Parse error RPC '%s': ", rpc_name_simple))
                               if (private$.peek_token() == "stream") { private$.consume_token(); fn$client_streaming <- TRUE }
                               req_msg_short_name <- private$.consume_token()
                               private$.expect_token(")", sprintf("Parse error RPC '%s': ", rpc_name_simple))
                               private$.expect_token("returns", sprintf("Parse error RPC '%s': ", rpc_name_simple))
                               private$.expect_token("(", sprintf("Parse error RPC '%s': ", rpc_name_simple))
                               if (private$.peek_token() == "stream") { private$.consume_token(); fn$server_streaming <- TRUE }
                               res_msg_short_name <- private$.consume_token()
                               private$.expect_token(")", sprintf("Parse error RPC '%s': ", rpc_name_simple))

                               lookup_descriptor <- function(short_name, pkg_name, logger) {
                                 fq_name <- if (nzchar(pkg_name)) sprintf("%s.%s", pkg_name, short_name) else short_name
                                 desc <- RProtoBuf::P(fq_name)
                                 if (is.null(desc) && nzchar(pkg_name)) {
                                   logger$warn("Could not find RProtoBuf Descriptor with FQN '%s'. This can happen in some environments. Falling back to short name '%s'.", fq_name, short_name)
                                   desc <- RProtoBuf::P(short_name)
                                 }
                                 if (is.null(desc)) stop(sprintf("Cannot find Descriptor for type '%s'. Was the proto compiled correctly?", fq_name))
                                 return(list(desc = desc, fq_name = fq_name))
                               }

                               req_info <- lookup_descriptor(req_msg_short_name, private$pkg_name, private$logger)
                               res_info <- lookup_descriptor(res_msg_short_name, private$pkg_name, private$logger)

                               fn$RequestType <- req_info$desc
                               fn$RequestTypeName <- req_info$fq_name
                               fn$ResponseType <- res_info$desc
                               fn$ResponseTypeName <- res_info$fq_name

                               fn$name <- if (nzchar(private$pkg_name)) sprintf("/%s.%s/%s", private$pkg_name, service_name_arg, rpc_name_simple) else sprintf("/%s/%s", service_name_arg, rpc_name_simple)
                               private$parsed_services[[rpc_name_simple]] <- fn
                             },
                             .doService = function() {
                               service_name_val <- private$.consume_token()
                               private$.expect_token("{", sprintf("Parse error Service '%s': ", service_name_val))
                               while(!is.null(private$.peek_token()) && private$.peek_token() != "}") {
                                 if (private$.peek_token() == "rpc") { private$.consume_token(); private$.doRPC(service_name_val) }
                                 else { private$.consume_token() }
                               }
                               private$.expect_token("}", sprintf("Parse error Service '%s': ", service_name_val))
                             }
                           ),
                           public = list(
                             #' @description
                             #' Creates a new `ProtoParser` object.
                             #'
                             #' This step is lazy and does not read or process the file until `$compile()`
                             #' or `$parse()` are called. It only checks for the file's existence and
                             #' performs initial tokenization.
                             #'
                             #' @param file A string, the path to the `.proto` file.
                             #' @param logger An optional logger object (e.g., from the 'lgr' package)
                             #'   for logging messages. If `NULL`, a default `GrpcLogger` is used.
                             #' @return A new `ProtoParser` object.
                             initialize = function(file, logger = NULL) {
                               private$logger <- logger %||% GrpcLogger$new()
                               if (!file.exists(file)) {
                                 stop(sprintf("Proto file not found: '%s'", file), call. = FALSE)
                               }
                               private$file_path <- normalizePath(file)
                               lines <- readLines(private$file_path)
                               raw_tokens <- unlist(strsplit(lines, '(^//.*$|\\s+|(?=[{}();]))', perl = TRUE))
                               private$tokens <- Filter(nzchar, raw_tokens)
                             },

                             #' @description
                             #' Compiles the `.proto` file using `RProtoBuf::readProtoFiles`.
                             #'
                             #' @details
                             #' This method is a prerequisite for `$parse()`. It robustly tells `RProtoBuf`
                             #' where to find the file using the `dirs` argument, avoiding fragile changes
                             #' to the global working directory.
                             #'
                             #' @return The `ProtoParser` object, invisibly, to allow for chaining.
                             compile = function() {
                               # THE DEFINITIVE FIX: Pass the full, absolute file path directly.
                               # The `private$file_path` is already normalized from initialize().
                               RProtoBuf::readProtoFiles(private$file_path)

                               private$is_compiled <- TRUE
                               return(invisible(self))
                             },


                             #' @description
                             #' Parses the tokenized `.proto` file to extract service definitions.
                             #'
                             #' This method must be called after `$compile()`. It scans the file for
                             #' `package`, `service`, and `rpc` declarations to build an internal
                             #' representation of the services. It will overwrite any previously
                             #' parsed services.
                             #'
                             #' @return The `ProtoParser` object, invisibly, to allow for chaining.
                             parse = function() {
                               if (!private$is_compiled) {
                                 stop("The proto file must be compiled with `$compile()` before calling `$parse()`.")
                               }
                               private$current_token_idx <- 1
                               private$pkg_name <- ""
                               private$parsed_services <- list()
                               while(private$current_token_idx <= length(private$tokens)) {
                                 token <- private$.peek_token()
                                 if (is.null(token)) break
                                 if (token == "package") {
                                   private$.consume_token()
                                   private$pkg_name <- private$.consume_token()
                                   if (!is.null(private$.peek_token()) && private$.peek_token() == ";") private$.consume_token()
                                 } else if (token == "service") {
                                   private$.consume_token()
                                   private$.doService()
                                 } else {
                                   private$.consume_token()
                                 }
                               }
                               return(invisible(self))
                             },

                             #' @description
                             #' Retrieves the parsed gRPC service definitions.
                             #'
                             #' @return A named list where each element corresponds to an RPC method.
                             #'   The name of the element is the simple RPC name (e.g., "SayHello").
                             #'   Each element is a list containing:
                             #'   \itemize{
                             #'     \item \code{name}: The full RPC path (e.g., "/package.Service/RpcName").
                             #'     \item \code{f}: An identity function placeholder.
                             #'     \item \code{client_streaming}: A logical, `TRUE` if the client sends a stream.
                             #'     \item \code{server_streaming}: A logical, `TRUE` if the server returns a stream.
                             #'     \item \code{RequestType}: The `RProtoBuf::Descriptor` for the request message.
                             #'     \item \code{RequestTypeName}: The fully qualified name of the request message.
                             #'     \item \code{ResponseType}: The `RProtoBuf::Descriptor` for the response message.
                             #'     \item \code{ResponseTypeName}: The fully qualified name of the response message.
                             #'   }
                             get_services = function() {
                               return(private$parsed_services)
                             }
                           )
)

# NOTE: For this to work in a package, you will also need to:
# 1. Add `R6` and `RProtoBuf` to the `Imports` section of your DESCRIPTION file.
# 2. Add `import(R6)` to your `NAMESPACE` file, usually via an `#' @import R6` roxygen tag.
# 3. Define the `GrpcLogger` class and the `%||%` operator or import it (e.g., from `rlang`).
#    If `%||%` is custom, a simple definition would be:
#    `'%||%' <- function(a, b) if (is.null(a)) b else a`
