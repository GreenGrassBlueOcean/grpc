# In your R/utils.R

#' Provides a Default List of gRPC Server Hook Functions
#'
#' This function returns a list of named functions that can be used as lifecycle
#' hooks for a gRPC server started with `start_server()`. These default hooks
#' primarily log messages using the `futile.logger` package at various stages
#' of the server's lifecycle.
#'
#' Users can provide their own list of hook functions to `start_server()` to
#' customize server behavior, for example, for service registration/deregistration
#' (e.g., with Consul), custom metrics, or more detailed logging.
#'
#' @section Hook Functions and Parameters:
#' The C++ server core calls these R hook functions at specific points.
#' After recent changes, all hooks are called with a `params` argument,
#' which is an R list. For most hooks, this list will be empty.
#' The `bind` hook is a notable exception, receiving `params = list(port = <bound_port>)`.
#'
#' The default implementations are:
#' \itemize{
#'   \item `server_create(params)`: Logs when the gRPC server object is created.
#'   \item `queue_create(params)`: Logs when the completion queue is created.
#'   \item `bind(params)`: Logs the port the server will listen on (receives `params$port`).
#'   \item `server_start(params)`: Logs when the server has started listening.
#'   \item `run(params)`: Logs when the server enters its main event-processing loop.
#'   \item `shutdown(params)`: Logs when server shutdown is initiated.
#'   \item `stopped(params)`: Logs when the gRPC library has been shut down by the server.
#'   \item `exit(params = list())`: Logs when the `start_server` R function is exiting.
#'     (Typically called by `on.exit()` in R, hence `params = list()` for robustness).
#' }
#' The hooks `event_received` and `event_processed` were in the original nfultz version
#' but are not currently invoked by the `GreenGrassBlueOcean/grpc` C++ server code.
#'
#' @return A named `list` of functions, where each function corresponds to a
#'   gRPC server lifecycle hook.
#' @export
#' @importFrom futile.logger flog.trace flog.debug flog.info
#' @seealso \code{\link{start_server}}
#'
#' @examples
#' \dontrun{
#' # Get the default hooks
#' default_hooks <- grpc_default_hooks()
#'
#' # You could then customize one or more hooks:
#' my_custom_hooks <- default_hooks
#' my_custom_hooks$run <- function(params) {
#'   futile.logger::flog.info("My custom run hook: Server is now fully operational!")
#' }
#' my_custom_hooks$bind <- function(params) {
#'   if (!is.null(params$port)) {
#'     futile.logger::flog.info(paste("My bind: Server will use port", params$port))
#'     # Example: Register with a service discovery tool
#'     # register_service("my_grpc_service", params$port)
#'   }
#' }
#'
#' # And then pass them to start_server:
#' # start_server(impl, channel, hooks = my_custom_hooks)
#'
#' # To use a minimal set of hooks (or no hooks):
#' # start_server(impl, channel, hooks = list()) # No hooks
#' # start_server(impl, channel, hooks = list(bind = my_custom_hooks$bind)) # Only custom bind
#' }
grpc_default_hooks <- function() {
  list(
    server_create = function(params) { # Receives empty list from C++
      flog.trace('Default hook: gRPC server created')
    },
    queue_create = function(params) { # Receives empty list from C++
      flog.trace('Default hook: Completion queue created and registered')
    },
    bind = function(params) { # Receives list(port = ...) from C++
      if (!is.null(params$port)) {
        flog.debug(paste('Default hook: gRPC service will listen on port', params$port))
      } else {
        flog.debug('Default hook: gRPC bind hook called (port info not in params).')
      }
    },
    server_start = function(params) { # Receives empty list from C++
      flog.trace(paste('Default hook: gRPC server_start called'))
    },
    run = function(params) { # Receives empty list from C++
      flog.info(paste('Default hook: gRPC service run (main loop is starting)'))
    },
    shutdown = function(params) { # Receives empty list from C++
      flog.info('Default hook: gRPC service shutdown initiated')
    },
    stopped = function(params) { # Receives empty list from C++
      flog.debug('Default hook: gRPC service stopped (after C++ grpc_shutdown)')
    },
    exit = function(params = list()) { # Called by R's on.exit() or directly
      flog.trace('Default hook: Server R function (start_server) is exiting')
    }
  )
}
