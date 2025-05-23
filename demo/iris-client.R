#' Iris Classifier Client Demo
#'
#' Connects to the Iris Classifier gRPC server (expected to be running
#' on localhost:50051), sends Iris feature data, and receives classification results.
#' Note: Requires the 'iris-server' demo to be running on port 50051.
#' @demo iris-client
#' @importFrom futile.logger flog.info flog.error flog.warn flog.threshold INFO
#' @importFrom RProtoBuf P # Assuming read_services uses this
#' @importFrom stats rnorm # Example uses rnorm for bad data

# --- Setup ---
# library(grpc)
# library(RProtoBuf)
# library(futile.logger)

# Set logger level
flog.threshold(INFO)

flog.info("--- Iris Classifier Client Demo Starting ---")

# --- Define Paths and Read Service Definitions ---
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

# --- Connect to Server ---
server_address <- "localhost:50051"
flog.info("Attempting to connect to server at: %s", server_address)
flog.info("(Ensure the 'iris-server' demo is running on this port).")

client <- NULL
tryCatch({
  client <- grpc::grpc_client(impl, server_address)
}, error = function(e) {
  flog.error("Failed to create gRPC client for '%s': %s", server_address, e$message)
  stop("Client creation failed. Is the server running?")
})

# Verify client structure - adjust service/method names as needed!
# Example: Assume service is 'IrisClassifier' and method is 'Classify'
service_method_name <- "IrisClassifier.Classify" # Adjust if needed (e.g., just "Classify")
if (!service_method_name %in% names(client)) {
  stop(sprintf("Client object does not contain expected method: %s", service_method_name))
}
# Helper function to call RPC and handle errors
call_classify <- function(request_msg) {
  response <- NULL
  tryCatch({
    # Adjust client access based on actual structure
    response <- client[[service_method_name]]$call(request_msg)
  }, error = function(e) {
    flog.error("RPC call failed: %s", e$message)
    # Optionally return a specific error indicator or NULL
  })
  response
}

# --- Single Classification Example ---
flog.info("--- Sending single classification request ---")
tryCatch({
  # Adjust client access and field names based on actual structure
  msg_single <- client[[service_method_name]]$build(sepal_length = 5.1,
                                                    sepal_width = 3.5,
                                                    petal_length = 1.4,
                                                    petal_width = 0.2) # Example: Setosa features

  res_single <- call_classify(msg_single)

  if (!is.null(res_single)) {
    # Access response fields - adjust field names as needed
    flog.info('Single Result: Species=%s, Probability=%.4f',
              res_single$species, res_single$probability)
    # Add checks for status if the response includes it
    if ("status" %in% names(res_single) && !is.null(res_single$status) && res_single$status$code != 0) {
      flog.warn("Received non-OK status for single request: %s", res_single$status$message)
    }
  } else {
    flog.warn("Single classification call returned NULL (likely failed).")
  }
}, error = function(e){
  # Catch errors in building the message itself
  flog.error("Error during single classification build/call: %s", e$message)
})


# --- Batch Classification Example ---
flog.info("--- Sending batch classification requests (sampling iris data) ---")
# Ensure column names match expected field names or adjust build() call
# Original code used Sepal.Length etc., proto might use sepal_length
# For robustness, let's rename iris columns to match common proto style
iris_data <- iris
names(iris_data) <- gsub("\\.", "_", tolower(names(iris_data))) # Convert . to _ and lower

# Sample some rows
set.seed(42) # for reproducibility
df_sample <- iris_data[sample(nrow(iris_data), 5), ] # Sample 5 for brevity

for (n in seq_len(nrow(df_sample))) {
  row_data <- df_sample[n, ]
  flog.info("Sending request for row %d: Sepal L=%.1f, W=%.1f | Petal L=%.1f, W=%.1f",
            n, row_data$sepal_length, row_data$sepal_width, row_data$petal_length, row_data$petal_width)

  tryCatch({
    # Adjust client access and field names
    msg_batch <- client[[service_method_name]]$build(
      sepal_length = row_data$sepal_length,
      sepal_width  = row_data$sepal_width,
      petal_length = row_data$petal_length,
      petal_width  = row_data$petal_width)

    res_batch <- call_classify(msg_batch)

    if (!is.null(res_batch)) {
      # Adjust field names as needed
      flog.info(' -> Batch Result %d: Species=%s, Probability=%.4f',
                n, res_batch$species, res_batch$probability)
      if ("status" %in% names(res_batch) && !is.null(res_batch$status) && res_batch$status$code != 0) {
        flog.warn("Received non-OK status for batch request %d: %s", n, res_batch$status$message)
      }
    } else {
      flog.warn(" -> Batch classification call %d returned NULL (likely failed).", n)
    }
  }, error = function(e){
    flog.error("Error during batch classification build/call for row %d: %s", n, e$message)
  })
  Sys.sleep(0.1) # Optional pause
}


# --- Intentionally Failing Classification Example ---
flog.info("--- Sending intentionally invalid request (negative sepal_length) ---")
tryCatch({
  # Adjust client access and field names
  msg_fail <- client[[service_method_name]]$build(sepal_length = -5.0,
                                                  sepal_width = stats::rnorm(1, 3), # add some random other values
                                                  petal_length = stats::rnorm(1, 4),
                                                  petal_width = stats::rnorm(1, 1))

  res_fail <- call_classify(msg_fail)

  flog.info("Response for invalid request:")
  if (!is.null(res_fail)) {
    # Use str() to see the full structure, especially the status
    utils::str(as.list(res_fail))
    # Check specifically for a status field if the proto defines one
    if ("status" %in% names(res_fail) && !is.null(res_fail$status)) {
      flog.info("Status code: %d, Message: %s", res_fail$status$code, res_fail$status$message)
    } else {
      flog.warn("Response received, but no 'status' field found to check for error.")
    }
  } else {
    flog.warn("Invalid classification call returned NULL (likely failed).")
  }
}, error = function(e){
  flog.error("Error during invalid classification build/call: %s", e$message)
})


flog.info("--- Iris Classifier Client Demo Finished ---")
