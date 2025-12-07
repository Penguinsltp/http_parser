///|
using @http_parser {
  parse_message,
  type HttpMessage,
  type HttpRequest,
  type HttpResponse,
  type HttpParserError,
}

///|
using @sys {get_cli_args, exit}

///|
using @fs {read_file_to_string}

///|
fn main {
  let args = get_cli_args()
  let program = if args.length() == 0 { "http_parser_cli" } else { args[0] }
  if args.length() <= 1 {
    println("❗ 需要提供 HTTP 报文或文件路径。")
    print_usage(program)
    exit(1)
    return
  }
  let exit_code = match resolve_input(args) {
    Ok(raw) => handle_message(raw)
    Err(message) => {
      println("❌ " + message)
      print_usage(program)
      1
    }
  }
  exit(exit_code)
}

///|
fn resolve_input(args : Array[String]) -> Result[String, String] {
  guard args.length() > 1 else {
    return Err("请提供 HTTP 报文或者文件路径。")
  }
  let first = args[1]
  if first == "--file" {
    guard args.length() > 2 else {
      return Err("--file 选项需要提供文件路径。")
    }
    let path = args[2]
    load_file_content(path)
  } else if first == "--inline" {
    guard args.length() > 2 else {
      return Err("--inline 选项需要提供报文内容。")
    }
    Ok(args[2])
  } else {
    load_file_content(first)
  }
}

///|
fn handle_message(raw : String) -> Int {
  match parse_message(raw) {
    Ok(HttpMessage::Request(req)) => {
      print_request(req)
      0
    }
    Ok(HttpMessage::Response(resp)) => {
      print_response(resp)
      0
    }
    Err(err) => {
      println("解析失败: " + format_error(err))
      2
    }
  }
}

///|
fn print_request(req : HttpRequest) -> Unit {
  println("== HTTP Request ==")
  println("Method : " + req.verb)
  println("Target : " + req.target)
  println(
    "Version: HTTP/" +
    req.version.major.to_string() +
    "." +
    req.version.minor.to_string(),
  )
  print_headers(req.headers)
  print_body(req.body)
}

///|
fn print_response(resp : HttpResponse) -> Unit {
  println("== HTTP Response ==")
  println("Status : " + resp.status_code.to_string() + " " + resp.reason)
  println(
    "Version: HTTP/" +
    resp.version.major.to_string() +
    "." +
    resp.version.minor.to_string(),
  )
  print_headers(resp.headers)
  print_body(resp.body)
}

///|
fn print_headers(headers : Array[(String, String)]) -> Unit {
  if headers.length() == 0 {
    println("Headers: <none>")
    return
  }
  println("Headers:")
  for entry in headers {
    println("  " + entry.0 + ": " + entry.1)
  }
}

///|
fn print_body(body : String) -> Unit {
  if body.length() == 0 {
    println("Body   : <empty>")
  } else {
    println("Body   :")
    println(body)
  }
}

///|
fn format_error(err : HttpParserError) -> String {
  match err {
    HttpParserError::EmptyMessage => "报文为空。"
    HttpParserError::MissingHeaderBodyBoundary =>
      "缺少空行分隔头部和主体。"
    HttpParserError::MissingRequestLine => "请求首行缺失。"
    HttpParserError::MissingResponseLine => "响应首行缺失。"
    HttpParserError::InvalidRequestLine(line) => "非法请求首行: " + line
    HttpParserError::InvalidResponseLine(line) => "非法响应首行: " + line
    HttpParserError::InvalidHttpVersion(token) =>
      "不支持的 HTTP 版本: " + token
    HttpParserError::InvalidHeaderLine(line) => "非法头部: " + line
    HttpParserError::InvalidStatusCode(value) => "非法状态码: " + value
    HttpParserError::InvalidContentLength(value) =>
      "非法 Content-Length: " + value
    HttpParserError::IncompleteBody(expected~, actual~) =>
      "主体长度不足: 期望 " +
      expected.to_string() +
      " 字节，仅有 " +
      actual.to_string() +
      " 字节。"
    HttpParserError::UnsupportedTransferEncoding(value) =>
      "暂不支持的 Transfer-Encoding: " + value
  }
}

///|
fn print_usage(program : String) -> Unit {
  println("用法:")
  println(
    "  " + program + " --file <path>    # 从文件读取完整 HTTP 报文",
  )
  println(
    "  " +
    program +
    " --inline <text>  # 直接提供完整 HTTP 报文，注意自行加引号",
  )
  println(
    "  " +
    program +
    " <path>           # 兼容路径简写，与 --file 效果相同",
  )
}

///|
fn load_file_content(path : String) -> Result[String, String] {
  try {
    let content = read_file_to_string(path)
    Ok(content)
  } catch {
    @fs.IOError(message) => Err("读取文件失败: " + message)
  }
}
