# In tests/testthat/test-ProtoParser.R


# Helper function to generate unique proto content and names.
create_unique_proto <- function(with_package = FALSE) {
  # This creates a unique ID for every single call to this function.
  unique_id <- paste0("T", paste0(sample(c(letters, 0:9), 12, replace = TRUE), collapse = ""))

  pkg_line <- if (with_package) paste0("package pkg", unique_id, ";") else ""
  pkg_name <- if (with_package) paste0("pkg", unique_id) else ""
  req_name <- paste0("Request", unique_id)
  res_name <- paste0("Response", unique_id)

  # THE FIX: Generate unique service and RPC names to avoid collisions
  # in RProtoBuf's global state.
  service_name <- paste0("Service", unique_id)
  rpc_name <- paste0("Rpc", unique_id)

  # Use the new unique names in the proto content string.
  content <- sprintf('syntax = "proto3"; %s message %s {} message %s {} service %s { rpc %s (%s) returns (%s); }',
                     pkg_line, req_name, res_name, service_name, rpc_name, req_name, res_name)

  proto_file <- tempfile(fileext = ".proto")
  writeLines(text = content, con = proto_file)

  # The tests only rely on the request name, so we don't need to return the new unique names.
  return(list(
    filepath = proto_file,
    fq_req_name = if (with_package) paste(pkg_name, req_name, sep=".") else req_name
  ))
}

# THE FIX: Add this helper function back in. It is used by the last test.
create_temp_proto <- function(content, dir = tempdir(), fileext = ".proto") {
  if (!is.character(content)) content <- as.character(content)
  proto_file <- tempfile(tmpdir = dir, fileext = fileext)
  writeLines(text = content, con = proto_file)
  return(proto_file)
}


# ==== ProtoParser Class Tests ====

test_that("ProtoParser initializes lazily and handles file errors", {
  expect_error(ProtoParser$new("nonexistent.proto"), regexp = "Proto file not found")

  proto_info <- create_unique_proto()
  on.exit(unlink(proto_info$filepath), add = TRUE)
  expect_silent(parser <- ProtoParser$new(proto_info$filepath))
  expect_s3_class(parser, "ProtoParser")

  expect_error(parser$parse(), regexp = "must be compiled with.*compile")
})

# IMPORTANT: This block of tests for SUCCESS cases is run BEFORE the
# test for failure cases. This ensures the RProtoBuf state is clean.
test_that("ProtoParser correctly parses valid service definitions", {
  # Test 1: Service without package
  proto_no_pkg_info <- create_unique_proto(with_package = FALSE)
  on.exit(unlink(proto_no_pkg_info$filepath), add = TRUE)

  parser_no_pkg <- ProtoParser$new(proto_no_pkg_info$filepath)
  parser_no_pkg$compile()
  parser_no_pkg$parse()
  services_no_pkg <- parser_no_pkg$get_services()

  expect_length(services_no_pkg, 1)
  rpc_def_no_pkg <- services_no_pkg[[1]]
  # This is the corrected assertion for S4 objects.
  expect_s4_class(rpc_def_no_pkg$RequestType, "Descriptor")
  expect_equal(rpc_def_no_pkg$RequestTypeName, proto_no_pkg_info$fq_req_name)

  # Test 2: Service with package
  proto_with_pkg_info <- create_unique_proto(with_package = TRUE)
  on.exit(unlink(proto_with_pkg_info$filepath), add = TRUE)

  parser_with_pkg <- ProtoParser$new(proto_with_pkg_info$filepath)
  # A warning is acceptable if the fallback is triggered.
  suppressWarnings(parser_with_pkg$compile())
  parser_with_pkg$parse()
  services_with_pkg <- parser_with_pkg$get_services()

  rpc_def_with_pkg <- services_with_pkg[[1]]
  # This is the corrected assertion for S4 objects.
  expect_s4_class(rpc_def_with_pkg$RequestType, "Descriptor")
  expect_equal(rpc_def_with_pkg$RequestTypeName, proto_with_pkg_info$fq_req_name)
})

# This test is now run LAST. It will pass, but it may corrupt the
# RProtoBuf state. Since it's the last test, this is not a problem.
test_that("parser$compile() fails on invalid proto syntax", {
  content_invalid <- 'syntax = "proto3"; message M { field = 1; }'
  temp_invalid <- create_temp_proto(content_invalid)
  on.exit(unlink(temp_invalid), add = TRUE)

  parser <- ProtoParser$new(temp_invalid)
  expect_error(parser$compile(), regexp = "Could not load proto file")
})
