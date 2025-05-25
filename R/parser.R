#' Create stub object from protobuf spec
#'
#' @param file the spec file
#' @return a stub data structure (the 'impl' object)
#' @importFrom RProtoBuf readProtoFiles P
#' @importFrom methods is
#' @export
read_services <- function(file){
  SERVICE = "service"
  RPC = "rpc"
  RETURNS = "returns" # Keyword used by parser to navigate .proto structure
  STREAM = "stream"   # Keyword for identifying streaming RPCs
  PACKAGE = "package"

  services <- list() # This list will be populated and returned
  pkg <- ""           # Stores the package name declared in the .proto file (e.g., "helloworld")

  # Step 1: Let RProtoBuf process the .proto file.
  # This is crucial as it loads the message definitions, allowing RProtoBuf::P()
  # to retrieve Descriptor objects for message types later.
  RProtoBuf::readProtoFiles(file)

  # Step 2: Read the .proto file content for manual token-based parsing.
  # This parsing identifies services, RPC methods, and their request/response types.
  lines <- readLines(file)
  # Tokenize: split by whitespace or around delimiters like {}, (), ;
  # Also removes single-line comments starting with //
  tokens <- Filter(f=nchar, unlist(strsplit(lines, '(^//.*$|\\s+|(?=[{}();]))', perl=TRUE)))

  # Nested function to parse an RPC method definition (e.g., rpc SayHello(Request) returns (Reply);)
  # It's called when an "rpc" token is encountered within a service block.
  # - i: current index in the `tokens` array.
  # - service_name: name of the current service being parsed (e.g., "Greeter").
  doRPC <- function(i, service_name) {
    rpc_name = tokens[i+1] # Simple name of the RPC method (e.g., "SayHello")

    # Initialize the list for this RPC method.
    # 'f = I' sets a placeholder for the R handler function, which the user will define later.
    fn <- list(f=I)

    current_param_type_key <- "RequestType" # State variable: expecting "RequestType" first, then "ResponseType"

    # Loop through tokens for this RPC definition: MyRPC ( ReqType ) returns ( RespType ) ;
    # Stop at the closing '}' of the service block or the ';' ending the RPC definition.
    while(tokens[i] != '}' && tokens[i] != ';'){

      if(tokens[i] == '('){ # Marks the start of (RequestType) or (ResponseType)
        i <- i + 1          # Move to the token immediately after '('

        is_stream <- tokens[i] == STREAM # Check if the 'stream' keyword is present
        if(is_stream){
          i <- i + 1      # If 'stream' is present, move past it to the message type name
        }

        message_type_name_short <- tokens[i] # Short name of the message type (e.g., "HelloRequest")

        # Construct the fully qualified message type name (e.g., "helloworld.HelloRequest").
        # This uses 'pkg', which is the package name declared at the top of the .proto file.
        full_message_type_name <- if (nzchar(pkg)) sprintf("%s.%s", pkg, message_type_name_short) else message_type_name_short

        # Retrieve the RProtoBuf::Descriptor object for this message type using RProtoBuf::P().
        descriptor_object <- RProtoBuf::P(full_message_type_name)

        # Validate that a Descriptor object was successfully retrieved.
        if (!methods::is(descriptor_object, "Descriptor")) {
          stop(paste0("Could not find RProtoBuf Descriptor for message type '", full_message_type_name,
                      "' for RPC '", rpc_name, "' in service '", service_name,
                      "'. Ensure .proto file ('", file, "') is correct, defines this message, ",
                      "and RProtoBuf::readProtoFiles() succeeded."))
        }

        # Store the RProtoBuf::Descriptor object directly into fn$RequestType or fn$ResponseType.
        # This is the key change to align with the nfultz demo's structure and the
        # expectations of the GreenGrassBlueOcean/R/server.R and R/client.R files.
        fn[[current_param_type_key]] <- descriptor_object

        # The 'is_stream' boolean could be stored alongside the descriptor if needed,
        # e.g., fn[[current_param_type_key]] <- list(descriptor = descriptor_object, stream = is_stream).
        # However, for direct nfultz demo compatibility and the current server/client R scripts,
        # storing the descriptor directly is sufficient.

        # If RequestType was just processed, the next type will be ResponseType.
        if (current_param_type_key == "RequestType") {
          current_param_type_key <- "ResponseType"
        }
      }
      i <- i + 1 # Move to the next token in the RPC definition
    }

    # Construct and store the fully qualified gRPC method path (e.g., "/helloworld.Greeter/SayHello")
    fn$name <- if (nzchar(pkg)) sprintf("/%s.%s/%s", pkg, service_name, rpc_name) else sprintf("/%s/%s", service_name, rpc_name)

    # Add this method's definition ('fn') to the main 'services' list.
    # It's keyed by the simple RPC name (e.g., services$SayHello <- fn_definition_for_SayHello).
    services[[rpc_name]] <<- fn
    return(i) # Return the current token index (advanced past the RPC definition)
  }

  # Nested function to parse a service definition block (e.g., service Greeter { ... }).
  # It's called when a "service" token is encountered in the .proto file.
  # - i: current index in the `tokens` array.
  doServices <- function(i){
    service_name <- tokens[i+1] # The token after "service" is its name (e.g., "Greeter").

    # Loop through tokens within the service block until the closing '}' is found.
    while(tokens[i] != '}') {
      if(tokens[i] == RPC){ # If an "rpc" token is found, call doRPC to parse the method.
        i <- doRPC(i, service_name) # doRPC will advance 'i' past the RPC definition.
      }
      i <- i + 1 # Move to the next token within the service block.
    }
    return(i) # Return the token index (should be at or after the service block's '}').
  }

  # Step 3: Main parsing loop. Iterate through all tokens from the .proto file.
  i <- 1
  while(i <= length(tokens)){
    if(tokens[i] == PACKAGE) {
      # Found the 'package' directive. The next token is the package name.
      pkg <- tokens[i+1];
      i <- i + 1 # Also consume the package name token, so advance main loop index.
    }
    else if(tokens[i] == SERVICE){
      # Found the 'service' directive. Call doServices to handle the entire service block.
      # doServices will advance 'i' past the end of the service block.
      i <- doServices(i)
    }
    i <- i + 1 # Advance to the next token for the main loop.
  }

  return(services) # Return the populated list of service method definitions.
}
