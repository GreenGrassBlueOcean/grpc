#' gRPC Logger
#'
#' @description
#' An R6 class for handling logging within the gRPC package.
#' It attempts to use 'futile.logger' if available, otherwise falls back
#' to base R messaging/warning/stopping functions.
#'
#' @details
#' This logger provides a consistent interface for logging messages at different
#' severity levels. Log messages are constructed using `sprintf`-like behavior:
#' if multiple arguments are passed to a logging method (e.g., `logger$info(fmt, val1, val2)`),
#' the first argument is treated as an `sprintf` format string, and subsequent arguments
#' are values to be formatted into it. If a single argument is passed, it is treated
#' as a literal message.
#'
#' Example:
#' ```
#' logger <- GrpcLogger$new()
#' logger$info("Request for ID %s processed in %.2f seconds.", request_id, duration)
#' logger$warn("A literal warning message with a % sign.")
#' ```
#'
#' When `futile.logger` is used, any literal percent signs (`%`) in the final
#' formatted message are automatically escaped to `%%` before being passed to
#' `futile.logger` functions. This is to prevent conflicts with `futile.logger`'s
#' internal use of `sprintf` for its own layout formatting.
#'
#' The internal mechanism for checking `futile.logger` availability can be
#' overridden during initialization for testing purposes by providing a
#' custom `can_flog_fun`. The underlying implementation (`..can_flog_impl`)
#' can also have its `requireNamespace` dependency injected for fine-grained testing.
#'
#' @section Private Members:
#' Internal implementation details:
#' \itemize{
#'   \item `..can_flog_impl(level_func_name, .req_ns_fun)`: The default function for
#'     checking `futile.logger` function availability.
#'   \item `.can_flog`: The function (either default or injected) that will actually
#'     be called by public methods to determine if `futile.logger` should be used.
#'   \item `.sprintf_message(...)`: A helper to format `...` arguments into a single
#'     string, using `sprintf` if multiple arguments are provided.
#' }
#'
#' @importFrom futile.logger flog.info flog.warn flog.error flog.fatal flog.debug flog.trace
#' @export
GrpcLogger <- R6::R6Class("GrpcLogger",
                          private = list(
                            # ..can_flog_impl: Default implementation for checking futile.logger availability.
                            # @param level_func_name Character, e.g., "flog.info".
                            # @param .req_ns_fun Function to use for requireNamespace (for testing).
                            ..can_flog_impl = function (level_func_name, .req_ns_fun = base::requireNamespace) {
                              if (!.req_ns_fun("futile.logger", quietly = TRUE)) {
                                return(FALSE)
                              }
                              tryCatch({
                                # Ensure the fetched object is indeed a function
                                func_obj <- getFromNamespace(level_func_name, "futile.logger")
                                is.function(func_obj)
                              }, error = function(e) FALSE)
                            },

                            # .can_flog: Actual function used to check futile.logger. Set in initialize.
                            .can_flog = NULL,

                            # .sprintf_message: Formats ... arguments.
                            # If multiple arguments, treats first as sprintf format string.
                            # If single argument, returns it as a character string.
                            .sprintf_message = function(...) {
                              args <- list(...)
                              if (length(args) == 0) {
                                return("")
                              }
                              if (length(args) == 1) {
                                # Single argument, convert to character.
                                # Percent signs here are literal and will be escaped later if passed to flog.*
                                return(as.character(args[[1]]))
                              }
                              # Multiple arguments: first is format string, rest are values for sprintf.
                              # Percent signs in args[[1]] are sprintf specifiers.
                              # Literal percent signs from args[[2]], args[[3]], etc. are preserved by sprintf.
                              return(do.call(sprintf, args))
                            }
                          ),

                          public = list(
                            #' @description
                            #' Initialize a new GrpcLogger object.
                            #' @param can_flog_fun (optional) A function to override the internal
                            #'   `.can_flog` mechanism for checking `futile.logger` availability.
                            #'   Primarily for testing. The function should take one argument (the
                            #'   `futile.logger` function name string, e.g., "flog.info") and return
                            #'   `TRUE` if `futile.logger` should be used, `FALSE` otherwise.
                            initialize = function(can_flog_fun = NULL) {
                              if (is.null(can_flog_fun)) {
                                private$.can_flog <- function(level_func_name) {
                                  private$..can_flog_impl(level_func_name) # Calls ..can_flog_impl with its default .req_ns_fun
                                }
                              } else {
                                if (!is.function(can_flog_fun)) {
                                  stop("'can_flog_fun' must be a function or NULL.", call. = FALSE)
                                }
                                private$.can_flog <- can_flog_fun
                              }
                            },

                            #' @description Log an informational message.
                            #' @param ... Arguments to be formatted into a log message. If multiple
                            #'   arguments are provided, the first is treated as an `sprintf` format
                            #'   string and the rest as values. If a single argument is provided, it is
                            #'   treated as a literal message.
                            #' @param .envir The environment in which to evaluate expressions for
                            #'   `futile.logger`. Defaults to the calling environment of this method.
                            info = function (..., .envir = parent.frame()) {
                              final_message <- private$.sprintf_message(...)
                              # Escape all literal '%' in final_message before passing to flog.*
                              # because flog.* uses sprintf internally with its own layout string.
                              final_message_for_flog <- gsub("%", "%%", final_message, fixed = TRUE)

                              if (private$.can_flog("flog.info")) {
                                futile.logger::flog.info(final_message_for_flog, .envir = .envir) # <-- FIXED
                              } else {
                                # Base message() doesn't need further % escaping from final_message
                                message(paste0("INFO: ", final_message))
                              }
                            },

                            #' @description Log a warning message.
                            #' @param ... Arguments to be formatted (see `info` method description).
                            #' @param .envir The environment for `futile.logger` evaluation.
                            warn = function (..., .envir = parent.frame()) {
                              final_message <- private$.sprintf_message(...)
                              final_message_for_flog <- gsub("%", "%%", final_message, fixed = TRUE)
                              if (private$.can_flog("flog.warn")) {
                                futile.logger::flog.warn(final_message_for_flog, .envir = .envir) # <-- FIXED
                              } else {
                                warning(paste0("WARN: ", final_message), call. = FALSE)
                              }
                            },

                            #' @description Log an error message.
                            #' @param ... Arguments to be formatted (see `info` method description).
                            #' @param .envir The environment for `futile.logger` evaluation.
                            error = function (..., .envir = parent.frame()) {
                              final_message <- private$.sprintf_message(...)
                              final_message_for_flog <- gsub("%", "%%", final_message, fixed = TRUE)
                              if (private$.can_flog("flog.error")) {
                                futile.logger::flog.error(final_message_for_flog, .envir = .envir) # <-- FIXED
                              } else {
                                warning(paste0("ERROR: ", final_message), call. = FALSE)
                              }
                            },

                            #' @description Log a fatal error message and stop execution.
                            #' @param ... Arguments to be formatted (see `info` method description).
                            #' @param .envir The environment for `futile.logger` evaluation.
                            fatal = function (..., .envir = parent.frame()) {
                              final_message <- private$.sprintf_message(...)
                              final_message_for_flog <- gsub("%", "%%", final_message, fixed = TRUE)
                              if (private$.can_flog("flog.fatal")) {
                                futile.logger::flog.fatal(final_message_for_flog, .envir = .envir) # <-- FIXED
                              } else {
                                stop(paste0("FATAL: ", final_message), call. = FALSE)
                              }
                            },

                            #' @description Log a debug message.
                            #' @param ... Arguments to be formatted (see `info` method description).
                            #' @param .envir The environment for `futile.logger` evaluation.
                            debug = function (..., .envir = parent.frame()) {
                              final_message <- private$.sprintf_message(...)
                              final_message_for_flog <- gsub("%", "%%", final_message, fixed = TRUE)
                              if (private$.can_flog("flog.debug")) {
                                futile.logger::flog.debug(final_message_for_flog, .envir = .envir) # <-- FIXED
                              } else {
                                message(paste0("DEBUG: ", final_message))
                              }
                            },

                            #' @description Log a trace message.
                            #' @param ... Arguments to be formatted (see `info` method description).
                            #' @param .envir The environment for `futile.logger` evaluation.
                            trace = function (..., .envir = parent.frame()) {
                              final_message <- private$.sprintf_message(...)
                              final_message_for_flog <- gsub("%", "%%", final_message, fixed = TRUE)
                              if (private$.can_flog("flog.trace")) {
                                futile.logger::flog.trace(final_message_for_flog, .envir = .envir) # <-- FIXED
                              } else {
                                message(paste0("TRACE: ", final_message))
                              }
                            }
                          )
)
