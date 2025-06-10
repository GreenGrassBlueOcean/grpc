# Put this in an R file in your package, e.g., R/logging.R or R/utils.R

#' Configure gRPC C-core Logging Environment Variables
#'
#' Sets or unsets the `GRPC_TRACE` and `GRPC_VERBOSITY` environment variables,
#' which control the built-in logging and tracing detail of the underlying
#' gRPC C-core library. These settings are primarily for deep debugging of
#' gRPC's internal operations and can be very verbose.
#'
#' @details
#' **Important Timing:** For these settings to reliably take effect, this
#' function should typically be called *before* the gRPC C-core is initialized.
#' In most R packages using gRPC, this means calling it:
#' \itemize{
#'   \item Before `library(grpc)` if the package initializes gRPC on load.
#'   \item Or, at least before the first call to gRPC operations like
#'         `grpc_client()` or `start_server()` if initialization is deferred.
#' }
#' If called after gRPC has initialized, changes might not apply or might only
#' affect new gRPC objects (like channels or servers) created subsequently.
#'
#' **Available Tracers (`trace_options`):**
#' The gRPC C-core offers various tracers. For an up-to-date list, refer to the
#' official gRPC documentation (e.g., search for "gRPC Tracing" or check
#' `grpc/src/core/lib/debug/trace.cc` in the gRPC source).
#' Common tracers include:
#' `api`, `call_error`, `channel`, `client_channel`, `connectivity_state`,
#' `cq_poller` (or `polling` for older versions), `http`, `http1`, `http2`,
#' `initialization`, `metadata`, `op_failure`, `pick_first`, `round_robin`,
#' `server_channel`, `subchannel`, `tcp`, `timer`, `timer_check`.
#' Using `"all"` enables all tracers and is extremely verbose.
#'
#' **Verbosity Levels (`verbosity`):**
#' \itemize{
#'   \item `"DEBUG"`: Enables debug logging, very verbose.
#'   \item `"INFO"`: Enables informational logs.
#'   \item `"ERROR"`: Enables only error logs (least verbose).
#' }
#'
#' @param trace_options A character string or vector specifying the gRPC tracers
#'   to enable.
#'   \itemize{
#'     \item A single string with comma-separated tracer names (e.g., `"api,channel,http"`).
#'     \item A character vector of tracer names (e.g., `c("api", "channel", "http")`),
#'           which will be combined with commas.
#'     \item `"all"` to enable all available tracers.
#'     \item `NULL` or `character(0)` to unset (disable) `GRPC_TRACE`.
#'   }
#'   Defaults to `NULL` (GRPC_TRACE is unset).
#' @param verbosity A single character string for the gRPC C-core log verbosity.
#'   Allowed values are `"DEBUG"`, `"INFO"`, `"ERROR"`.
#'   `NULL` will unset (disable) `GRPC_VERBOSITY`.
#'   Defaults to `NULL` (GRPC_VERBOSITY is unset).
#' @param quiet Logical. If `TRUE`, suppresses messages from this function
#'   indicating which environment variables were set/unset. Defaults to `FALSE`.
#'
#' @return Invisibly returns a list containing the *previous* values of
#'   `GRPC_TRACE` and `GRPC_VERBOSITY`. This allows for restoring prior settings.
#'   If an environment variable was not previously set, its corresponding value
#'   in the returned list will be `NULL`.
#'
#' @export
#' @examples
#' \dontrun{
#' # It's best to call this early, e.g., before library(grpc) or gRPC operations.
#'
#' # Example: Enable API and channel tracing with DEBUG verbosity
#' old_settings <- rgrpc_set_core_logging(
#'   trace_options = c("api", "channel"),
#'   verbosity = "DEBUG"
#' )
#' print("gRPC C-core logging configured. Proceed with gRPC operations.")
#' # library(grpc)
#' # ... your gRPC code ...
#'
#' # Example: Turn off all gRPC C-core tracing and verbosity
#' rgrpc_set_core_logging(trace_options = NULL, verbosity = NULL)
#' print("gRPC C-core logging disabled.")
#'
#' # Example: Enable all tracers with INFO verbosity
#' # rgrpc_set_core_logging(trace_options = "all", verbosity = "INFO")
#'
#' # To restore previous settings (if you saved them):
#' # if (exists("old_settings")) {
#' #   rgrpc_set_core_logging(
#' #     trace_options = old_settings$GRPC_TRACE,
#' #     verbosity = old_settings$GRPC_VERBOSITY
#' #   )
#' #   print("Restored previous gRPC C-core logging settings.")
#' # }
#' }
rgrpc_set_core_logging <- function(trace_options = NULL, verbosity = NULL, quiet = FALSE) {
  # Store current (old) values to return them
  # Sys.getenv returns "" if unset, use NA_character_ with unset argument to distinguish
  old_trace_val <- Sys.getenv("GRPC_TRACE", unset = NA_character_)
  old_verbosity_val <- Sys.getenv("GRPC_VERBOSITY", unset = NA_character_)

  # --- Handle GRPC_TRACE ---
  if (is.null(trace_options) || (is.character(trace_options) && length(trace_options) == 0)) {
    Sys.unsetenv("GRPC_TRACE")
    if (!quiet) message("gRPC C-core: GRPC_TRACE environment variable unset.")
  } else {
    if (!is.character(trace_options)) {
      warning("'trace_options' should be a character string/vector or NULL. GRPC_TRACE not changed.")
    } else {
      trace_string <- paste(unique(trace_options), collapse = ",")
      Sys.setenv(GRPC_TRACE = trace_string)
      if (!quiet) message(paste("gRPC C-core: GRPC_TRACE set to:", shQuote(trace_string)))
    }
  }

  # --- Handle GRPC_VERBOSITY ---
  valid_verbosity_levels <- c("DEBUG", "INFO", "ERROR")
  if (is.null(verbosity)) {
    Sys.unsetenv("GRPC_VERBOSITY")
    if (!quiet) message("gRPC C-core: GRPC_VERBOSITY environment variable unset.")
  } else {
    if (!is.character(verbosity) || length(verbosity) != 1) {
      warning("'verbosity' should be a single string or NULL. GRPC_VERBOSITY not changed.")
    } else if (!toupper(verbosity) %in% valid_verbosity_levels) {
      warning(paste(
        "'verbosity' level", shQuote(verbosity), "is invalid.",
        "Choose from:", paste(shQuote(valid_verbosity_levels), collapse = ", "),
        "or NULL. GRPC_VERBOSITY not changed."
      ))
    } else {
      Sys.setenv(GRPC_VERBOSITY = toupper(verbosity))
      if (!quiet) message(paste("gRPC C-core: GRPC_VERBOSITY set to:", shQuote(toupper(verbosity))))
    }
  }

  invisible(list(
    GRPC_TRACE = if (is.na(old_trace_val)) NULL else old_trace_val,
    GRPC_VERBOSITY = if (is.na(old_verbosity_val)) NULL else old_verbosity_val
  ))
}




# Internal helper to check if futile.logger functions are available
# Not exported.
.can_flog <- function(level_func_name) {
  if (!requireNamespace("futile.logger", quietly = TRUE)) return(FALSE)
  tryCatch({
    func <- getFromNamespace(level_func_name, "futile.logger")
    is.function(func)
  }, error = function(e) FALSE)
}

# Internal logging wrapper functions
# Not exported.
.log_info <- function(...) {
  if (.can_flog("flog.info")) { # Note the dot prefix for internal call
    futile.logger::flog.info(...)
  } else {
    message(paste0("INFO: ", ...)) # Optional fallback
  }
}

.log_error <- function(...) {
  if (.can_flog("flog.error")) { # Note the dot prefix
    futile.logger::flog.error(...)
  } else {
    warning(paste0("ERROR: ", ...), call. = FALSE) # Optional fallback
  }
}

.log_warn <- function(...) {
  if (.can_flog("flog.warn")) { # Note the dot prefix
    futile.logger::flog.warn(...)
  } else {
    warning(paste0("WARN: ", ...), call. = FALSE) # Optional fallback
  }
}

.log_fatal <- function(...) {
  if (.can_flog("flog.fatal")) { # Note the dot prefix
    futile.logger::flog.fatal(...)
  } else {
    stop(paste0("FATAL: ", ...), call. = FALSE) # Optional fallback
  }
}
