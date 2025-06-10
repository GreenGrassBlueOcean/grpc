# In tests/testthat/test-GrpcClient.R

testthat::skip_if_not_installed("mockery")
testthat::skip_if_not_installed("RProtoBuf")

# ==== Test Setup ====

# Mock RProtoBuf objects and helpers (unchanged)
mock_descriptor <- function(name) {
  structure(list(name = name), class = c("Descriptor", "MessageDescriptor"))
}
dummy_req_descriptor <- mock_descriptor("TestRequest")
dummy_res_descriptor <- mock_descriptor("TestResponse")
mock_rprotobuf_new <- function(descriptor, ...) {
  msg <- structure(c(list(.type = descriptor$name), list(...)), class = c("RProtoBuf Message", "Message"))
  attr(msg, "descriptor") <- descriptor
  msg
}
mock_rprotobuf_read <- function(descriptor, payload) {
  mock_rprotobuf_new(descriptor, from_payload = payload)
}
mock_rprotobuf_serialize <- function(message, connection) {
  charToRaw(paste0("serialized:", message$name))
}
mock_rprotobuf_descriptor <- function(msg) {
  attr(msg, "descriptor")
}
dummy_services_spec <- list(
  SayHello = list(
    name             = "/helloworld.Greeter/SayHello",
    RequestType      = dummy_req_descriptor,
    ResponseType     = dummy_res_descriptor,
    RequestTypeName  = "helloworld.HelloRequest",
    ResponseTypeName = "helloworld.HelloReply"
  )
)
MockLogger <- R6::R6Class("MockLogger", inherit = GrpcLogger,
                          public = list(
                            initialize = function(...) {},
                            info = function(...) {}, warn = function(...) {}, debug = function(...) {}
                          )
)

# THE DEFINITIVE FIX: The "Spy Field" pattern for mock R6 objects.
MockProtoParser <- R6::R6Class("MockProtoParser", inherit = ProtoParser,
                               public = list(
                                 # Public fields to hold our "spy" mock objects for inspection.
                                 compile_spy = NULL,
                                 parse_spy = NULL,
                                 get_services_spy = NULL,

                                 initialize = function(file = NULL, logger = NULL) {
                                   # In initialize, create FRESH mock functions and assign them to our spy fields.
                                   self$compile_spy <- mockery::mock(invisible(self))
                                   self$parse_spy <- mockery::mock(invisible(self))
                                   self$get_services_spy <- mockery::mock(dummy_services_spec)
                                 },

                                 # The public interface methods OVERRIDE the parent's methods.
                                 # They simply call our spy fields, creating a "seam" for testing.
                                 compile = function() { self$compile_spy() },
                                 parse = function() { self$parse_spy() },
                                 get_services = function() { self$get_services_spy() }
                               )
)

# ==== Tests for GrpcClient R6 Class ====

test_that("GrpcClient initialization works and uses parser correctly", {
  # 1. Create an instance of our robust mock parser.
  mock_parser <- MockProtoParser$new()

  # 2. Inject the mock parser and mock logger.
  expect_no_error(
    client <- GrpcClient$new(parser = mock_parser, channel = "localhost:50051", logger = MockLogger$new())
  )

  # 3. Verify the spy fields were called by the public interface methods.
  mockery::expect_called(mock_parser$compile_spy, 1)
  mockery::expect_called(mock_parser$parse_spy, 1)
  mockery::expect_called(mock_parser$get_services_spy, 1)

  expect_s3_class(client, "GrpcClient")
})

test_that("Client stub's $build() and $call() methods work", {
  mock_parser <- MockProtoParser$new()
  client <- GrpcClient$new(parser = mock_parser, channel = "localhost:50051", logger = MockLogger$new())

  # Test the $build() method
  mock_new_spy <- mockery::mock()
  testthat::with_mocked_bindings(
    client$stubs$SayHello$build(name = "Test Client"),
    new = mock_new_spy, .package = "RProtoBuf"
  )
  mockery::expect_called(mock_new_spy, 1)

  # Test the $call() method
  call_func <- client$stubs$SayHello$call
  request_msg <- mock_rprotobuf_new(dummy_req_descriptor, name = "R")
  mock_cpp_call <- mockery::mock(charToRaw("valid response"))

  mockery::stub(call_func, 'robust_grpc_client_call', mock_cpp_call)
  mockery::stub(call_func, 'RProtoBuf::serialize', mock_rprotobuf_serialize)
  mockery::stub(call_func, 'RProtoBuf::descriptor', mock_rprotobuf_descriptor)
  mockery::stub(call_func, 'RProtoBuf::read', mock_rprotobuf_read)

  response <- call_func(request_msg)

  mockery::expect_called(mock_cpp_call, 1)
  expect_s3_class(response, "Message")
})

test_that("Client stub's $call() handles input validation", {
  mock_parser <- MockProtoParser$new()
  client <- GrpcClient$new(parser = mock_parser, channel = "localhost:50051", logger = MockLogger$new())
  call_func <- client$stubs$SayHello$call

  expect_error(call_func("not a message"), "not an RProtoBuf Message")

  wrong_msg <- mock_rprotobuf_new(mock_descriptor("WrongType"))
  mockery::stub(call_func, 'RProtoBuf::descriptor', mock_rprotobuf_descriptor)
  expect_error(call_func(wrong_msg), "not the expected type")
})
