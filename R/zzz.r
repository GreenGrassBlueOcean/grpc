# In R/zzz.R

# Global variable to track if gRPC was initialized by this package
.grpc_initialized_by_pkg <- FALSE

# In R/zzz.R
# In R/zzz.R
.onLoad <- function(libname, pkgname) {
  # Check an environment variable or R option for verbose loading
  # For example, Sys.getenv("R_GRPC_LOAD_VERBOSE", unset = "FALSE") == "TRUE"
  # Or getOption("grpc.load.verbose", default = FALSE)
  verbose_load <- Sys.getenv("R_GRPC_LOAD_VERBOSE", unset = "FALSE") == "TRUE"

  # if (verbose_load) {
  #   packageStartupMessage(paste("Attempting to load protos for package:", pkgname, "from lib: ", libname))
  # }

  proto_dir_rel <- "examples"
  proto_dir_abs <- system.file(proto_dir_rel, package = pkgname)

  # if (verbose_load) {
  #   packageStartupMessage(paste(".onLoad: Resolved proto directory:", proto_dir_abs))
  # }

  protos_loaded_successfully <- TRUE # Flag to track overall success
  if (nzchar(proto_dir_abs) && dir.exists(proto_dir_abs)) {
    package_protos <- c("helloworld.proto") # Add other core protos if needed

    for (pfile_basename in package_protos) {
      full_proto_path <- file.path(proto_dir_abs, pfile_basename)
      if (file.exists(full_proto_path)) {
        # if (verbose_load) {
        #   packageStartupMessage(paste("Loading proto file via .onLoad:", full_proto_path))
        # }
        tryCatch({
          RProtoBuf::readProtoFiles(files = full_proto_path)
          # if (verbose_load) {
          #   packageStartupMessage(paste("Successfully processed proto file:", full_proto_path))
          # }
        }, error = function(e) {
          # This is an important message, so maybe always show it, or make it a warning
          warning(paste0("grpc package: Error loading proto file '",
                         pfile_basename, "' in .onLoad: ", e$message), call. = FALSE)
          protos_loaded_successfully <- FALSE
        })
      } else {
        # if (verbose_load) { # Or maybe this is important enough to always show as a warning
        #   packageStartupMessage(paste0(".onLoad: Proto file not found: ", full_proto_path))
        # }
        # Consider if a missing core proto should be a warning
        warning(paste0("grpc package: Core proto file '", pfile_basename, "' not found at expected location."), call. = FALSE)
        protos_loaded_successfully <- FALSE # if this is critical
      }
    }
  } else {
    # if (verbose_load) {
    #   packageStartupMessage(paste0(".onLoad: Proto directory 'inst/", proto_dir_rel, "' not found."))
    # }
    # This could also be a warning if essential protos are expected
    warning(paste0("grpc package: Proto directory 'inst/", proto_dir_rel, "' not found."), call. = FALSE)
    protos_loaded_successfully <- FALSE # if this is critical
  }

  # A single summary message
  if (protos_loaded_successfully && !verbose_load) {
    # Optionally, a very brief success message if not verbose, or no message on success
    # packageStartupMessage("grpc: Core protobufs loaded.")
  } else if (verbose_load) {
    # packageStartupMessage("grpc: .onLoad processing complete.")
  }
  # The "Ensure gRPC C-core..." message is probably good to keep for .onAttach instead.
}

.onAttach <- function(libname, pkgname) {
  # This message is more appropriate for .onAttach as it's about runtime use
  packageStartupMessage("Package 'grpc' version ", utils::packageVersion("grpc"), " attached. ",
                        "Ensure gRPC C-core is initialized by server/client functions if used directly.")
  # You could also print info about setting log levels here if you have the R functions for it
  # packageStartupMessage("Use rgrpc_set_log_level() or rgrpc_set_core_logging() to adjust C++ log verbosity.")
}

.onUnload <- function(libpath) {
  packageStartupMessage("Package 'grpc' unloaded.")
  library.dynam.unload("grpc", libpath)
}


