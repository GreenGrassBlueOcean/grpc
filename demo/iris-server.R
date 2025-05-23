#' Iris Classifier Server Demo
#'
#' Starts a gRPC server implementing the Iris Classifier service.
#' It loads an rpart model trained on the iris dataset and provides a
#' 'Classify' method to predict the species based on input features.
#' Listens on port 50051 on all interfaces.
#' @demo iris-server
#' @importFrom futile.logger flog.info flog.error flog.warn flog.threshold INFO FATAL
#' @importFrom RProtoBuf P readProtoFiles new # Assuming new() and P() are needed
#' @importFrom rpart rpart # Import specific function
#' @importFrom stats predict terms # Import specific functions
#' @importFrom jsonlite toJSON # Import specific function
#' @importFrom methods is # For type checking

# --- Setup ---
# library(grpc)
# library(RProtoBuf)
# library(futile.logger)
# library(rpart)
# library(jsonlite)
# library(stats) # predict, terms
# library(methods) # is

# Set logger level
flog.threshold(INFO)

flog.info("--- Iris Classifier Server Demo Starting ---")

# --- Train Model (Global Environment for Simplicity in Demo) ---
# This is okay for a demo, but in a real application, consider
# loading a pre-trained model or managing the model object differently.
flog.info("Training rpart model on iris dataset...")
tryCatch({
  iris_data <- iris
  # Ensure consistent naming with potential proto definitions
  names(iris_data) <- gsub("\\.", "_", tolower(names(iris_data)))
  # Train the model
  fit <- rpart::rpart(species ~ ., iris_data) # Use explicit namespace
  flog.info("Model training complete.")
  # Basic model validation
  if (!methods::is(fit, "rpart")) {
    stop("Model training did not result in an rpart object.")
  }
  # Get expected feature names from the model's terms
  expected_features <- attr(stats::terms(fit), "term.labels")
  flog.info("Model expects features: %s", paste(expected_features, collapse=", "))
}, error = function(e) {
  flog.fatal("Failed to train the rpart model: %s", e$message)
  stop("Model training failed.")
})


# --- Read Service Definition ---
spec_path <- system.file('examples/iris_classifier.proto', package = 'grpc')

if (!file.exists(spec_path)) {
  stop("Could not find iris_classifier.proto in grpc package examples.")
}

flog.info("Reading service definition from: %s", spec_path)
impl <- NULL
tryCatch({
  impl <- grpc::read_services(spec_path) # Use explicit namespace
}, error = function(e) {
  flog.error("Failed to read proto file '%s': %s", spec_path, e$message)
  stop("Proto file reading failed.")
})

# --- Implement Service Method ---
# Verify method and get Response Type descriptors
# Adjust names based on actual structure from read_services
# Example: Assume service is 'IrisClassifier' and method is 'Classify'
classify_method_name <- "Classify" # Adjust if needed (e.g., "IrisClassifier.Classify")
if (!classify_method_name %in% names(impl)) {
  stop(sprintf("Implementation object missing expected method: %s", classify_method_name))
}

# Get Response Message Descriptors (adjust access as needed)
IrisClassResponse <- impl[[classify_method_name]]$ResponseType$proto # Adjust name if needed
IrisStatus <- RProtoBuf::P("iris.Status") # Get Status descriptor if needed - ADJUST NAME
if (is.null(IrisClassResponse) || is.null(IrisStatus)) {
  stop("Could not extract needed Response/Status message descriptors.")
}

# Define Classify implementation
flog.info("Defining Classify implementation...")
impl[[classify_method_name]]$f <- function(request) {
  # Input 'request' is already an RProtoBuf message object

  # Log received data
  # Use tryCatch as as.list might fail on malformed requests
  request_list <- tryCatch(as.list(request), error = function(e) list(error="Failed to convert request to list"))
  flog.info('Data received for scoring: %s', jsonlite::toJSON(request_list, auto_unbox = TRUE))

  response <- tryCatch({
    # Validate input features (presence and basic type/value check)
    missing_features <- setdiff(expected_features, names(request))
    if (length(missing_features) > 0) {
      stop(sprintf("Missing required features: %s", paste(missing_features, collapse=", ")))
    }

    # Check for non-positive values (as in original code)
    for (v in expected_features) {
      feature_value <- request[[v]]
      if (!is.numeric(feature_value) || length(feature_value) != 1) {
        stop(sprintf("Feature '%s' is not a single numeric value.", v))
      }
      # Original check was > 0, which allows 0. Adjust if needed.
      if (feature_value <= 0) { # Check for non-positive
        stop(sprintf('Non-positive value (%.2f) provided for feature %s', feature_value, v))
      }
    }

    # Perform prediction using the globally defined 'fit' model
    # predict requires a data.frame or list with matching names
    scores <- stats::predict(fit, newdata = request_list, type = "prob") # Use list, predict probabilities
    i <- which.max(scores[1, ]) # Predict gives matrix, take first row
    cls <- colnames(scores)[i] # Species names are column names for type="prob"
    p <- scores[1, i]

    flog.info('Predicted class: %s (p=%.4f)', cls, p)

    # Create success response - Adjust message name and fields if needed
    RProtoBuf::new(IrisClassResponse, species = cls, probability = p)

  }, error = function(e) {
    # Handle errors during validation or prediction
    error_msg <- sprintf("Classification failed: %s", e$message)
    flog.error(error_msg)
    # Create error response - Adjust message name and fields if needed
    RProtoBuf::new(IrisClassResponse, status = RProtoBuf::new(IrisStatus, code = 1, message = error_msg))
  })

  # Return the response object (either success or error response)
  response
}

# --- Start Server ---
server_address <- "0.0.0.0:50051"
flog.info("Starting Iris Classifier gRPC server on: %s", server_address)

server_hooks <- list(
  server_start = function(params){
    flog.info("Server startup hook triggered.")
  },
  exit = function() {
    flog.info("--- Iris Classifier Server Demo Exiting ---")
  }
)

tryCatch({
  grpc::start_server(impl, server_address, hooks = server_hooks) # Use explicit namespace
  flog.info("start_server returned (server likely shut down).")
}, error = function(e) {
  flog.fatal("Failed to start or run gRPC server: %s", e$message)
  stop("Server failed.")
})

flog.info("--- Iris Classifier Server Demo Script End (Server may still be running if not shut down) ---")
