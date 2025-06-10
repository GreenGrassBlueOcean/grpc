# In tests/testthat/test-grpc-logger.R

# ==== GrpcLogger Class Tests ====

test_that("GrpcLogger can be initialized and has public methods", {
  expect_silent(logger_default <- GrpcLogger$new())
  expect_s3_class(logger_default, "GrpcLogger"); expect_s3_class(logger_default, "R6")
  expect_true(is.function(logger_default$.__enclos_env__$private$.can_flog))

  custom_can_flog <- function(level_name) { TRUE }
  expect_silent(logger_custom <- GrpcLogger$new(can_flog_fun = custom_can_flog))
  expect_s3_class(logger_custom, "GrpcLogger")
  expect_equal(logger_custom$.__enclos_env__$private$.can_flog, custom_can_flog)

  expect_error(GrpcLogger$new(can_flog_fun = "not_a_function"),
               "'can_flog_fun' must be a function or NULL.")

  expected_methods <- c("initialize", "info", "warn", "error", "fatal", "debug", "trace")
  # Check against the class definition's public_methods
  expect_true(all(expected_methods %in% names(GrpcLogger$public_methods)))
})

# --- Test Fallback Logging (when .can_flog is false) ---
test_that("GrpcLogger falls back to base R with correct message formatting", {
  logger <- GrpcLogger$new(can_flog_fun = function(level_func_name) FALSE)

  # Using fixed = TRUE for exact string matching with expect_message/warning/error
  expect_message(logger$info("Test simple info"), "INFO: Test simple info", fixed = TRUE)
  expect_warning(logger$warn("Test simple warn"), "WARN: Test simple warn", fixed = TRUE)
  expect_warning(logger$error("Test simple error"), "ERROR: Test simple error", fixed = TRUE)
  expect_error(logger$fatal("Test simple fatal"), "FATAL: Test simple fatal", fixed = TRUE)
  expect_message(logger$debug("Test simple debug"), "DEBUG: Test simple debug", fixed = TRUE)
  expect_message(logger$trace("Test simple trace"), "TRACE: Test simple trace", fixed = TRUE)

  expect_message(logger$info("Info: %s %d", "val", 123), "INFO: Info: val 123", fixed = TRUE)
  expect_warning(logger$warn("Warn: %s", "problem"), "WARN: Warn: problem", fixed = TRUE)

  expect_message(logger$info("Rate is 50%"), "INFO: Rate is 50%", fixed = TRUE)
  expect_warning(logger$warn("Decrease of 25% is bad."), "WARN: Decrease of 25% is bad.", fixed = TRUE)
})


# --- Test Logging when futile.logger IS available ---
if (requireNamespace("futile.logger", quietly = TRUE) && requireNamespace("mockery", quietly = TRUE)) {

  test_that("GrpcLogger uses mocked flog.* with correctly formatted and escaped messages", {
    logger <- GrpcLogger$new(can_flog_fun = function(level_func_name) TRUE)

    # Create mocks allowing multiple calls
    mock_flog_info  <- mockery::mock(NULL, cycle = TRUE) # Allow multiple calls
    mock_flog_warn  <- mockery::mock(NULL, cycle = TRUE) # Allow multiple calls
    mock_flog_error <- mockery::mock(NULL, cycle = TRUE) # Allow multiple calls
    # For fatal, it stops, so one call is usually what's tested before an error.
    # If you had a scenario testing multiple fatal calls (unlikely before error), cycle = TRUE would be needed.
    mock_flog_fatal <- mockery::mock(stop("FATAL: flog.fatal called via mock")) # Default (cycle=FALSE) is fine as it stops
    mock_flog_debug <- mockery::mock(NULL, cycle = TRUE) # Allow multiple calls
    mock_flog_trace <- mockery::mock(NULL, cycle = TRUE) # Allow multiple calls

    # Stub all flog functions (this part remains the same)
    mockery::stub(logger$info,  "futile.logger::flog.info",  mock_flog_info)
    mockery::stub(logger$warn,  "futile.logger::flog.warn",  mock_flog_warn)
    mockery::stub(logger$error, "futile.logger::flog.error", mock_flog_error)
    mockery::stub(logger$fatal, "futile.logger::flog.fatal", mock_flog_fatal)
    mockery::stub(logger$debug, "futile.logger::flog.debug", mock_flog_debug)
    mockery::stub(logger$trace, "futile.logger::flog.trace", mock_flog_trace)

    # --- Test flog.info ---
    logger$info("A literal message for info.") # Call 1
    logger$info("Info formatted: %s, num: %d.", "text_val", 456) # Call 2
    logger$info("Info with 50% literal percent.") # Call 3
    logger$info("Info value: %s.", "ID_XYZ%") # Call 4

    mockery::expect_called(mock_flog_info, 4) # Expect 4 total calls now
    all_args_info <- mockery::mock_args(mock_flog_info) # Get all calls' arguments

    # Check arguments for each call
    expect_equal(all_args_info[[1]][[1]], "A literal message for info.")
    expect_true(is.environment(all_args_info[[1]]$.envir))

    expect_equal(all_args_info[[2]][[1]], "Info formatted: text_val, num: 456.")
    expect_true(is.environment(all_args_info[[2]]$.envir))

    expect_equal(all_args_info[[3]][[1]], "Info with 50%% literal percent.")
    expect_true(is.environment(all_args_info[[3]]$.envir))

    expect_equal(all_args_info[[4]][[1]], "Info value: ID_XYZ%%.")
    expect_true(is.environment(all_args_info[[4]]$.envir))

    # --- Test flog.warn ---
    logger$warn("A literal warning with 100% impact.") # Call 1
    logger$warn("Warning code: %d", 789) # Call 2

    mockery::expect_called(mock_flog_warn, 2)
    all_args_warn <- mockery::mock_args(mock_flog_warn)

    expect_equal(all_args_warn[[1]][[1]], "A literal warning with 100%% impact.")
    expect_true(is.environment(all_args_warn[[1]]$.envir))
    expect_equal(all_args_warn[[2]][[1]], "Warning code: 789")
    expect_true(is.environment(all_args_warn[[2]]$.envir))

    # --- Test flog.error ---
    logger$error("Error: %s failed with code %x.", "ProcessA", 255)
    mockery::expect_called(mock_flog_error, 1)
    args_error1 <- mockery::mock_args(mock_flog_error)[[1]]
    expect_equal(args_error1[[1]], "Error: ProcessA failed with code ff.")
    expect_true(is.environment(args_error1$.envir))

    # --- Test flog.fatal ---
    expect_error(logger$fatal("Fatal condition: %s.", "System Halt"),
                 "FATAL: flog.fatal called via mock", fixed = TRUE)
    mockery::expect_called(mock_flog_fatal, 1) # mock_flog_fatal was not cycle=TRUE, so it expects only 1 call
    args_fatal1 <- mockery::mock_args(mock_flog_fatal)[[1]]
    expect_equal(args_fatal1[[1]], "Fatal condition: System Halt.")
    expect_true(is.environment(args_fatal1$.envir))

    # --- Test flog.debug ---
    logger$debug("Debug message with data: %s", "0xCAFEBABE")
    mockery::expect_called(mock_flog_debug, 1)
    args_debug1 <- mockery::mock_args(mock_flog_debug)[[1]]
    expect_equal(args_debug1[[1]], "Debug message with data: 0xCAFEBABE")
    expect_true(is.environment(args_debug1$.envir))

    # --- Test flog.trace ---
    logger$trace("Trace execution: step %d of %d.", 1, 10)
    mockery::expect_called(mock_flog_trace, 1)
    args_trace1 <- mockery::mock_args(mock_flog_trace)[[1]]
    expect_equal(args_trace1[[1]], "Trace execution: step 1 of 10.")
    expect_true(is.environment(args_trace1$.envir))
  })
} else {
  testthat::skip("futile.logger or mockery not available, skipping GrpcLogger futile.logger integration tests.")
}

# --- Test the original ..can_flog_impl helper itself ---
test_that("Original ..can_flog_impl helper works as expected", {
  logger <- GrpcLogger$new()

  if (requireNamespace("futile.logger", quietly = TRUE)) {
    expect_true(logger$.__enclos_env__$private$..can_flog_impl("flog.info"))
    expect_true(logger$.__enclos_env__$private$..can_flog_impl("flog.warn"))
    expect_false(logger$.__enclos_env__$private$..can_flog_impl("flog.nonexistent"))
  } else {
    testthat::skip("futile.logger not available for positive ..can_flog_impl checks")
  }

  mock_rn_false_for_futile <- function(package, quietly = FALSE) {
    if (package == "futile.logger") {
      return(FALSE)
    }
    return(base::requireNamespace(package, quietly = quietly))
  }

  expect_false(
    logger$.__enclos_env__$private$..can_flog_impl("flog.info", .req_ns_fun = mock_rn_false_for_futile),
    label = "..can_flog_impl with injected mock requireNamespace returning FALSE for futile.logger"
  )
})
