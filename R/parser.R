#' Parse a .proto File to Define gRPC Service Stubs
#'
#' This function reads a `.proto` file, processes its content to identify
#' gRPC service definitions, RPC methods, and their associated request and
#' response message types. It leverages `RProtoBuf` to load the underlying
#' message definitions. The output is a list structure suitable for
#' initializing gRPC clients or servers within the `grpc` package.
#'
#' @details
#' The function performs two main steps:
#' \enumerate{
#'   \item It calls `RProtoBuf::readProtoFiles()` to parse the specified `.proto`
#'         file. This makes all defined message types globally known to `RProtoBuf`,
#'         allowing them to be instantiated using their fully qualified names.
#'   \item It then manually parses the `.proto` file content using a token-based
#'         approach to identify `package`, `service`, and `rpc` definitions.
#'         For each RPC method, it extracts:
#'         \itemize{
#'           \item The simple method name (e.g., "SayHello").
#'           \item The `RequestTypeName` (string) for the request message type.
#'           \item The `ResponseTypeName` (string) for the response message type.
#'           \item The fully qualified gRPC method `name` (e.g., "/package.Service/Method").
#'           \item A placeholder function `f` (initially `identity`).
#'           \item `client_streaming` and `server_streaming` boolean flags.
#'         }
#' }
#'
#' @param file A character string: the path to the `.proto` file to be parsed.
#' @return A named list. Each method's entry contains:
#'   \item{RequestType}{An `RProtoBuf::Descriptor` for the request.}
#'   \item{ResponseType}{An `RProtoBuf::Descriptor` for the response.}
#'   \item{RequestTypeName}{Character string: FQN of request type.}
#'   \item{ResponseTypeName}{Character string: FQN of response type.}
#'   \item{name}{Character string: full gRPC method path.}
#'   \item{f}{Function placeholder.}
#'   \item{client_streaming}{Boolean.}
#'   \item{server_streaming}{Boolean.}
#' @importFrom RProtoBuf readProtoFiles P name
#' @importFrom methods is
#' @export
read_services <- function(file){
  SERVICE = "service"; RPC = "rpc"; RETURNS = "returns"; STREAM = "stream"; PACKAGE = "package"
  services <- list(); pkg <- ""

  # Logging helpers (.can_flog, .log_info, etc. assumed to be in R/utils-logging.R)

  tryCatch({ RProtoBuf::readProtoFiles(file) }, error = function(e) {
    .log_error("RProtoBuf::readProtoFiles failed for '", file, "': ", e$message)
    stop(paste0("RProtoBuf::readProtoFiles failed for '", file, "': ", e$message), call. = FALSE)
  })
  if (!file.exists(file)) {
    .log_error("Proto file not found: '", file, "'")
    stop(paste0("Proto file not found: '", file, "'"), call. = FALSE)
  }
  lines <- readLines(file)
  tokens <- Filter(f=nzchar, unlist(strsplit(lines, '(^//.*$|\\s+|(?=[{}();]))', perl=TRUE)))

  doRPC <- function(current_token_idx, service_name_arg) {
    rpc_name_simple = tokens[current_token_idx + 1]
    # .log_info("read_services/doRPC: Parsing RPC '%s'", rpc_name_simple) # Less verbose
    fn <- list(f = I, client_streaming = FALSE, server_streaming = FALSE)
    i <- current_token_idx + 2
    # Simplified parsing, assuming valid structure, focusing on essentials
    if (tokens[i] != '(') stop(paste("Parse error RPC",rpc_name_simple,": expected '(' for req"), call.=F)
    i <- i + 1
    if (tokens[i] == STREAM) { fn$client_streaming <- TRUE; i <- i + 1 }
    req_msg_short_name <- tokens[i]; i <- i + 1
    if (tokens[i] != ')') stop(paste("Parse error RPC",rpc_name_simple,": expected ')' for req"), call.=F)
    i <- i + 1
    if (tokens[i] != RETURNS) stop(paste("Parse error RPC",rpc_name_simple,": expected 'returns'"), call.=F)
    i <- i + 1
    if (tokens[i] != '(') stop(paste("Parse error RPC",rpc_name_simple,": expected '(' for resp"), call.=F)
    i <- i + 1
    if (tokens[i] == STREAM) { fn$server_streaming <- TRUE; i <- i + 1 }
    res_msg_short_name <- tokens[i]; i <- i + 1
    if (tokens[i] != ')') stop(paste("Parse error RPC",rpc_name_simple,": expected ')' for resp"), call.=F)

    fq_req_name <- if (nzchar(pkg)) sprintf("%s.%s", pkg, req_msg_short_name) else req_msg_short_name
    fq_res_name <- if (nzchar(pkg)) sprintf("%s.%s", pkg, res_msg_short_name) else res_msg_short_name

    req_desc <- RProtoBuf::P(fq_req_name)
    if (is.null(req_desc) || !is(req_desc, "Descriptor")) {
      stop(paste0("Cannot find/validate Descriptor for RequestType '", fq_req_name, "' in RPC '", rpc_name_simple, "'"), call.=F)
    }
    fn$RequestType <- req_desc
    fn$RequestTypeName <- fq_req_name # Store for debugging/future

    res_desc <- RProtoBuf::P(fq_res_name)
    if (is.null(res_desc) || !is(res_desc, "Descriptor")) {
      stop(paste0("Cannot find/validate Descriptor for ResponseType '", fq_res_name, "' in RPC '", rpc_name_simple, "'"), call.=F)
    }
    fn$ResponseType <- res_desc
    fn$ResponseTypeName <- fq_res_name # Store for debugging/future

    fn$name <- if (nzchar(pkg)) sprintf("/%s.%s/%s", pkg, service_name_arg, rpc_name_simple) else sprintf("/%s/%s", service_name_arg, rpc_name_simple)
    services[[rpc_name_simple]] <<- fn

    current_token_after_response_paren <- i + 1
    if (current_token_after_response_paren <= length(tokens) && tokens[current_token_after_response_paren] == "{") {
      i <- current_token_after_response_paren + 1; open_braces <- 1
      while(i <= length(tokens) && open_braces > 0) {
        if (tokens[i] == "{") open_braces <- open_braces + 1
        else if (tokens[i] == "}") open_braces <- open_braces - 1
        i <- i + 1
      }
    } else { i <- current_token_after_response_paren }
    if (i <= length(tokens) && (tokens[i] == ';' || tokens[i] == '}')) return(i)
    else if (i > length(tokens)) return(i)
    else { .log_warn("read_services/doRPC: Unexpected token '%s' after RPC '%s'", tokens[i], rpc_name_simple); return(i) }
  }

  doServices <- function(current_token_idx){
    service_name_val <- tokens[current_token_idx + 1]
    i <- current_token_idx + 2
    if(i > length(tokens) || tokens[i] != '{') stop(paste("Parse error Service",service_name_val,": expected '{'"), call.=F)
    i <- i + 1
    while(i <= length(tokens) && tokens[i] != '}') {
      if(tokens[i] == RPC){ i <- doRPC(i, service_name_val)
      if (i <= length(tokens) && tokens[i] == ';') i <- i + 1
      } else { i <- i + 1 }
    }
    return(i)
  }
  idx <- 1
  while(idx <= length(tokens)){
    if(tokens[idx] == PACKAGE) {
      if ((idx + 1) <= length(tokens)) { pkg <- tokens[idx+1]; idx <- idx + 2
      } else stop("Parse error: 'package' keyword without name.", call.=F)
    } else if(tokens[idx] == SERVICE){ idx <- doServices(idx)
    if(idx <= length(tokens) && tokens[idx] == '}') idx <- idx + 1
    } else { idx <- idx + 1 }
  }
  return(services)
}
