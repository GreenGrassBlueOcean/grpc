# In R/zzz.R

# Global variable to track if gRPC was initialized by this package
.grpc_initialized_by_pkg <- FALSE

# In R/zzz.R
.onLoad <- function(libname, pkgname) {
  proto_dir_rel <- "examples"
  proto_dir_abs <- system.file(proto_dir_rel, package = pkgname) # Will point to inst/examples within your source during devtools::load_all

  packageStartupMessage(paste("Attempting to load protos for package:", pkgname, "from lib: ", libname))
  packageStartupMessage(paste(".onLoad: Resolved proto directory:", proto_dir_abs))


  if (nzchar(proto_dir_abs) && dir.exists(proto_dir_abs)) {
    package_protos <- c("helloworld.proto")

    for (pfile_basename in package_protos) {
      full_proto_path <- file.path(proto_dir_abs, pfile_basename)
      if (file.exists(full_proto_path)) {
        packageStartupMessage(paste("Loading proto file via .onLoad:", full_proto_path))
        tryCatch({ # Add tryCatch around readProtoFiles
          RProtoBuf::readProtoFiles(files = full_proto_path)
          packageStartupMessage(paste("Successfully processed proto file:", full_proto_path))
        }, error = function(e) {
          packageStartupMessage(paste("Error loading proto file", full_proto_path, "in .onLoad:", e$message))
        })
      } else {
        packageStartupMessage(paste0(".onLoad: Proto file not found: ", full_proto_path))
      }
    }
  } else {
    packageStartupMessage(paste0(".onLoad: Proto directory 'inst/", proto_dir_rel, "' not found."))
  }
  packageStartupMessage("Package 'grpc' .onLoad executed. Ensure gRPC C-core is initialized by server/client functions.")
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage("Package 'grpc' attached.")
}

.onUnload <- function(libpath) {
  packageStartupMessage("Package 'grpc' unloaded.")
  library.dynam.unload("grpc", libpath)
}

# utils::globalVariables(c("_grpc_fetch", "_grpc_run"))

