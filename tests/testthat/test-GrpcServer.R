# In tests/testthat/test-GrpcServer.R

testthat::skip_if_not_installed("mockery")
testthat::skip_if_not_installed("RProtoBuf")

# ==== Test Setup ====
mock_descriptor <- function(name) {
  structure(list(name = name), class = c("Descriptor", "MessageDescriptor"))
}
dummy_req_descriptor <- mock_descriptor("TestRequest")
dummy_res_descriptor <- mock_descriptor("TestResponse")
mock_rprotobuf_new <- function(descriptor, ...) {
  structure(c(list(.type = descriptor$name), list(...)), class = "RProtoBuf Message")
}
mock_rprotobuf_read <- function(descriptor, payload) {
  mock_rprotobuf_new(descriptor, payload = payload)
}
mock_rprotobuf_serialize <- function(message, connection) {
  as.raw(c(1, 2, 3))
}
test_handler <- function(request) {
  newResponse(reply = paste("ok:", request$payload))
}
valid_impl <- list(
  MyTestMethod = list(
    name = "/test.Service/MyTestMethod",
    RequestType = dummy_req_descriptor,
    ResponseType = dummy_res_descriptor,
    f = test_handler
  )
)

# ==== Tests for GrpcServer R6 Class ====

test_that("GrpcServer initialization and input validation works", {
  expect_no_error(GrpcServer$new(impl = valid_impl, channel = "localhost:1234"))
  expect_error(GrpcServer$new(impl = "not a list", channel = "localhost:1234"),
               "'impl' must be a list", fixed = TRUE)

  bad_impl_req <- valid_impl
  bad_impl_req$MyTestMethod$RequestType <- "not a descriptor"
  expect_error(
    GrpcServer$new(impl = bad_impl_req, channel = "localhost:1234"),
    "Invalid RequestType for method '/test.Service/MyTestMethod'. Expected RProtoBuf 'Descriptor'.",
    fixed = TRUE
  )
})

test_that("GrpcServer$run() calls C++ backend with correct arguments", {
  mock_run_cpp <- mockery::mock(NULL)
  server <- GrpcServer$new(impl = valid_impl, channel = "test.host:54321")
  mockery::stub(server$run, "robust_grpc_server_run", mock_run_cpp)
  server$run(duration_seconds = 99)
  mockery::expect_called(mock_run_cpp, 1)
})

test_that("Internal handler wrapper serializes and deserializes correctly", {
  mock_handler_f <- mockery::mock(list(message = "mocked response"))
  impl_with_mock_f <- list(
    MyTestMethod = list(
      name = "/test.Service/MyTestMethod",
      RequestType = dummy_req_descriptor,
      ResponseType = dummy_res_descriptor,
      f = mock_handler_f
    )
  )

  server <- GrpcServer$new(impl = impl_with_mock_f, channel = "localhost:1234")
  internal_handler <- server$.__enclos_env__$private$.server_handlers[[1]]

  mockery::stub(internal_handler, "RProtoBuf::read", mock_rprotobuf_read)
  mockery::stub(internal_handler, "RProtoBuf::serialize", mock_rprotobuf_serialize)

  response_bytes <- internal_handler(as.raw(c(10, 20)))

  mockery::expect_called(mock_handler_f, 1)
  expect_equal(response_bytes, as.raw(c(1, 2, 3)))
})

# ==== Tests for newResponse Helper ====

# DEFINITIVE FIX: The code to be mocked must be wrapped in {} to delay evaluation.
test_that("newResponse() works correctly when called from an attributed function", {
  my_handler <- function() {
    newResponse(field1 = "hello", field2 = 123)
  }
  attr(my_handler, "ResponseTypeDescriptor") <- dummy_res_descriptor

  # Temporarily redefine RProtoBuf::new using testthat's current mocker
  result <- testthat::with_mocked_bindings(
    # The code to run with the mock in place must be an unevaluated expression
    {
      my_handler()
    },
    # Subsequent named arguments define the mocks
    new = mock_rprotobuf_new,
    # Tell testthat to find 'new' in the 'RProtoBuf' package
    .package = "RProtoBuf"
  )

  # Assert on the output from our mock_rprotobuf_new
  expect_s3_class(result, "RProtoBuf Message")
  expect_equal(result$.type, "TestResponse")
  expect_equal(result$field1, "hello")
})

test_that("newResponse() throws informative errors for misconfigured callers", {
  bad_handler_no_attr <- function() { newResponse() }
  expect_error(bad_handler_no_attr(), "missing the 'ResponseTypeDescriptor' attribute")

  bad_handler_wrong_attr <- function() { newResponse() }
  attr(bad_handler_wrong_attr, "ResponseTypeDescriptor") <- "wrong type"
  expect_error(bad_handler_wrong_attr(), "not a valid RProtoBuf 'Descriptor' object")
})
