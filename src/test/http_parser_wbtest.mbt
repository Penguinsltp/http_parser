///|
/// HTTP 解析器白盒测试，覆盖请求与响应的核心路径。

///|
test "parses basic request message" {
  let raw = "GET /data HTTP/1.1\r\nHost: example.com\r\nUser-Agent: MoonBit\r\nContent-Length: 5\r\n\r\nHello"
  match @http_parser.parse_message(raw) {
    Ok(@http_parser.HttpMessage::Request(req)) => {
      assert_eq(req.verb, "GET")
      assert_eq(req.target, "/data")
      assert_eq(req.version.major, 1)
      assert_eq(req.version.minor, 1)
      match @http_parser.header_value(req.headers, "host") {
        Some(value) => assert_eq(value, "example.com")
        None => fail("missing host header")
      }
      match @http_parser.header_value(req.headers, "user-agent") {
        Some(value) => assert_eq(value, "MoonBit")
        None => fail("missing user agent header")
      }
      assert_eq(req.body, "Hello")
    }
    other => {
      let message =
        $|unexpected result: \{other}
      fail(message)
    }
  }
}

///|
test "parses basic response message" {
  let raw = "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nHello World"
  match @http_parser.parse_message(raw) {
    Ok(@http_parser.HttpMessage::Response(resp)) => {
      assert_eq(resp.status_code, 200)
      assert_eq(resp.reason, "OK")
      assert_eq(resp.version.major, 1)
      assert_eq(resp.version.minor, 1)
      match @http_parser.header_value(resp.headers, "content-length") {
        Some(value) => assert_eq(value, "11")
        None => fail("missing content-length header")
      }
      assert_eq(resp.body, "Hello World")
    }
    other => {
      let message =
        $|unexpected result: \{other}
      fail(message)
    }
  }
}

///|
test "reports body length mismatch" {
  let raw = "POST /submit HTTP/1.1\r\nContent-Length: 10\r\n\r\nHi"
  match @http_parser.parse_request(raw) {
    Err(@http_parser.HttpParserError::IncompleteBody(expected~, actual~)) => {
      assert_eq(expected, 10)
      assert_eq(actual, 2)
    }
    other => {
      let message =
        $|unexpected result: \{other}
      fail(message)
    }
  }
}

///|
test "rejects unsupported transfer encoding" {
  let raw = "GET /chunked HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
  match @http_parser.parse_request(raw) {
    Err(@http_parser.HttpParserError::UnsupportedTransferEncoding(value)) =>
      assert_eq(value, "chunked")
    other => {
      let message =
        $|unexpected result: \{other}
      fail(message)
    }
  }
}
