# Helper for proto creation using raw strings with a test-specific package
create_temp_helloworld_proto_test_r4_unary <- function(temp_dir = tempdir()) {
  # Using a unique package name for the test proto
  test_package_name <- paste0("helloworldtest", sample.int(1e9,1)) # Ensure uniqueness

  proto_content_template <- r"(
syntax = "proto3";

package {{TEST_PACKAGE_NAME}}; // Unique package name for test

service TestGreeter { // Unique service name
  rpc SayTestHello (TestHelloRequest) returns (TestHelloReply) {}
}

message TestHelloRequest {
  string name = 1;
}
message TestHelloReply {
  string message = 1;
}
)"
proto_content <- gsub("{{TEST_PACKAGE_NAME}}", test_package_name, proto_content_template, fixed = TRUE)

# Using a unique file name component as well
proto_file_basename <- paste0("test_helloworld_r4_", test_package_name, ".proto")
proto_file <- file.path(temp_dir, proto_file_basename)
cat(proto_content, file = proto_file)

return(list(filepath = proto_file,
            packagename = test_package_name,
            servicename = "TestGreeter",
            methodname = "SayTestHello",
            requesttype = "TestHelloRequest",
            replytype = "TestHelloReply"))
}

# You can put other common test helpers here in the future
