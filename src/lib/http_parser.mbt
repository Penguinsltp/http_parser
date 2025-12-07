///|
const ASCII_CR : Int = '\r'

///|
const ASCII_LF : Int = '\n'

///|
const ASCII_SPACE : Int = ' '

///|
const ASCII_TAB : Int = '\t'

///|
const ASCII_COLON : Int = ':'

///|
const ASCII_ZERO : Int = '0'

///|
const ASCII_NINE : Int = '9'

///|
const ASCII_LOWER_A : Int = 'a'

///|
const ASCII_LOWER_Z : Int = 'z'

///|
const ASCII_CASE_OFFSET : Int = 32

///|
pub struct HttpVersion {
  major : Int
  minor : Int
} derive(Show, Eq)

///|
pub struct HttpRequest {
  verb : String
  target : String
  version : HttpVersion
  headers : Array[(String, String)]
  body : String
} derive(Show, Eq)

///|
pub struct HttpResponse {
  version : HttpVersion
  status_code : Int
  reason : String
  headers : Array[(String, String)]
  body : String
} derive(Show, Eq)

///|
pub type Header = (String, String)

///|
pub enum HttpMessage {
  Request(HttpRequest)
  Response(HttpResponse)
} derive(Show, Eq)

///|
pub enum HttpParserError {
  EmptyMessage
  MissingHeaderBodyBoundary
  MissingRequestLine
  MissingResponseLine
  InvalidRequestLine(String)
  InvalidResponseLine(String)
  InvalidHttpVersion(String)
  InvalidHeaderLine(String)
  InvalidStatusCode(String)
  InvalidContentLength(String)
  IncompleteBody(expected~ : Int, actual~ : Int)
  UnsupportedTransferEncoding(String)
} derive(Show, Eq)

///|
pub fn parse_message(raw : String) -> Result[HttpMessage, HttpParserError] {
  let (lines, body_start) = match split_lines_and_body(raw) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  guard lines.length() > 0 else { return Err(EmptyMessage) }
  if starts_with_http(lines[0]) {
    match build_response(lines[:], raw, body_start) {
      Ok(response) => Ok(Response(response))
      Err(err) => Err(err)
    }
  } else {
    match build_request(lines[:], raw, body_start) {
      Ok(request) => Ok(Request(request))
      Err(err) => Err(err)
    }
  }
}

///|
pub fn parse_request(raw : String) -> Result[HttpRequest, HttpParserError] {
  let (lines, body_start) = match split_lines_and_body(raw) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  build_request(lines[:], raw, body_start)
}

///|
pub fn parse_response(raw : String) -> Result[HttpResponse, HttpParserError] {
  let (lines, body_start) = match split_lines_and_body(raw) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  build_response(lines[:], raw, body_start)
}

///|
pub fn header_value(headers : Array[Header], name : String) -> String? {
  let normalized = name[:].to_lower().to_string()
  for header in headers {
    if header.0 == normalized {
      return Some(header.1)
    }
  }
  None
}

///|
fn build_request(
  lines : ArrayView[String],
  raw : String,
  body_start : Int,
) -> Result[HttpRequest, HttpParserError] {
  guard lines.length() > 0 else { return Err(MissingRequestLine) }
  let (verb, target, version) = match parse_request_line(lines[0]) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let headers = match parse_headers(lines) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let body = match parse_body(headers.copy(), raw, body_start) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(HttpRequest::{ verb, target, version, headers, body })
}

///|
fn build_response(
  lines : ArrayView[String],
  raw : String,
  body_start : Int,
) -> Result[HttpResponse, HttpParserError] {
  guard lines.length() > 0 else { return Err(MissingResponseLine) }
  let (version, status_code, reason) = match parse_status_line(lines[0]) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let headers = match parse_headers(lines) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let body = match parse_body(headers.copy(), raw, body_start) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(HttpResponse::{ version, status_code, reason, headers, body })
}

///|
fn parse_request_line(
  line : String,
) -> Result[(String, String, HttpVersion), HttpParserError] {
  let tokens = split_ascii_whitespace(line)
  guard tokens.length() >= 3 else { return Err(InvalidRequestLine(line)) }
  let verb = tokens[0]
  let target = tokens[1]
  let version = match parse_http_version(tokens[2]) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok((verb, target, version))
}

///|
fn parse_status_line(
  line : String,
) -> Result[(HttpVersion, Int, String), HttpParserError] {
  match split_once_on_whitespace(line) {
    None => Err(InvalidResponseLine(line))
    Some((version_token, rest)) => {
      let version = match parse_http_version(version_token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match split_once_on_whitespace(rest) {
        None => Err(InvalidResponseLine(line))
        Some((status_token, reason_raw)) =>
          match parse_decimal(status_token) {
            None => Err(InvalidStatusCode(status_token))
            Some(value) => {
              let reason = ascii_trim(reason_raw)
              Ok((version, value, reason))
            }
          }
      }
    }
  }
}

///|
fn parse_headers(
  lines : ArrayView[String],
) -> Result[Array[Header], HttpParserError] {
  let headers : Array[Header] = []
  for index, line in lines.iter2() {
    if index == 0 || line.length() == 0 {
      continue
    }
    match parse_header_line(line) {
      Ok(header) => headers.push(header)
      Err(err) => return Err(err)
    }
  }
  Ok(headers)
}

///|
fn parse_header_line(line : String) -> Result[Header, HttpParserError] {
  match find_char(line, ASCII_COLON) {
    None => Err(InvalidHeaderLine(line))
    Some(pos) => {
      let name = ascii_trim(slice(line, 0, pos))[:].to_lower().to_string()
      let value = ascii_trim(slice(line, pos + 1, line.length()))
      Ok((name, value))
    }
  }
}

///|
fn parse_body(
  headers : Array[Header],
  raw : String,
  body_start : Int,
) -> Result[String, HttpParserError] {
  if header_value(headers, "transfer-encoding") is Some(value) {
    return Err(UnsupportedTransferEncoding(value))
  }
  let total_len = raw.length()
  if body_start >= total_len {
    return Ok("")
  }
  match header_value(headers, "content-length") {
    None => Ok(slice(raw, body_start, total_len))
    Some(len_value) =>
      match parse_decimal(len_value) {
        None => Err(InvalidContentLength(len_value))
        Some(expected) => {
          let available = total_len - body_start
          guard expected <= available else {
            return Err(IncompleteBody(expected~, actual=available))
          }
          Ok(slice(raw, body_start, body_start + expected))
        }
      }
  }
}

///|
fn split_lines_and_body(
  raw : String,
) -> Result[(Array[String], Int), HttpParserError] {
  guard raw.length() > 0 else { return Err(EmptyMessage) }
  match find_header_body_boundary(raw) {
    None => Err(MissingHeaderBodyBoundary)
    Some(boundary) => {
      let mut cursor = 0
      let lines : Array[String] = []
      while cursor < boundary {
        match find_crlf(raw, cursor) {
          None => return Err(MissingHeaderBodyBoundary)
          Some(line_end) => {
            lines.push(slice(raw, cursor, line_end))
            cursor = line_end + 2
          }
        }
      }
      Ok((lines, boundary + 4))
    }
  }
}

///|
fn split_ascii_whitespace(line : String) -> Array[String] {
  let tokens : Array[String] = []
  let len = line.length()
  let mut idx = 0
  let mut token_start : Int? = None
  while idx < len {
    let unit = line.code_unit_at(idx).to_int()
    if is_ascii_space(unit) {
      if token_start is Some(start) {
        tokens.push(slice(line, start, idx))
        token_start = None
      }
    } else if token_start is None {
      token_start = Some(idx)
    }
    idx = idx + 1
  }
  if token_start is Some(start) {
    tokens.push(slice(line, start, len))
  }
  tokens
}

///|
fn split_once_on_whitespace(line : String) -> (String, String)? {
  let len = line.length()
  let mut idx = 0
  while idx < len {
    let unit = line.code_unit_at(idx).to_int()
    if is_ascii_space(unit) {
      let left = slice(line, 0, idx)
      while idx < len && is_ascii_space(line.code_unit_at(idx).to_int()) {
        idx = idx + 1
      }
      let right = slice(line, idx, len)
      return Some((left, right))
    }
    idx = idx + 1
  }
  None
}

///|
fn parse_http_version(token : String) -> Result[HttpVersion, HttpParserError] {
  guard token.length() >= 6 else { return Err(InvalidHttpVersion(token)) }
  if !starts_with_http(token) {
    return Err(InvalidHttpVersion(token))
  }
  match find_char(token, '.') {
    None => Err(InvalidHttpVersion(token))
    Some(dot) => {
      let major_token = slice(token, 5, dot)
      let minor_token = slice(token, dot + 1, token.length())
      match (parse_decimal(major_token), parse_decimal(minor_token)) {
        (Some(major), Some(minor)) => Ok(HttpVersion::{ major, minor })
        _ => Err(InvalidHttpVersion(token))
      }
    }
  }
}

///|
fn parse_decimal(value : String) -> Int? {
  let trimmed = ascii_trim(value)
  let len = trimmed.length()
  if len == 0 {
    return None
  }
  let mut idx = 0
  let mut result = 0
  while idx < len {
    let unit = trimmed.code_unit_at(idx).to_int()
    if unit < ASCII_ZERO || unit > ASCII_NINE {
      return None
    }
    result = result * 10 + (unit - ASCII_ZERO)
    idx = idx + 1
  }
  Some(result)
}

///|
fn ascii_trim(value : String) -> String {
  let len = value.length()
  if len == 0 {
    return value
  }
  let mut start = 0
  let mut finish = len
  while start < finish && is_ascii_space(value.code_unit_at(start).to_int()) {
    start = start + 1
  }
  while finish > start &&
        is_ascii_space(value.code_unit_at(finish - 1).to_int()) {
    finish = finish - 1
  }
  if start == 0 && finish == len {
    return value
  }
  slice(value, start, finish)
}

///|
fn find_header_body_boundary(raw : String) -> Int? {
  let len = raw.length()
  if len < 4 {
    return None
  }
  let mut idx = 0
  while idx <= len - 4 {
    if is_crlf_sequence(raw, idx) && is_crlf_sequence(raw, idx + 2) {
      return Some(idx)
    }
    idx = idx + 1
  }
  None
}

///|
fn find_crlf(raw : String, start : Int) -> Int? {
  let len = raw.length()
  let mut idx = start
  while idx + 1 < len {
    if is_crlf_sequence(raw, idx) {
      return Some(idx)
    }
    idx = idx + 1
  }
  None
}

///|
fn is_crlf_sequence(raw : String, start : Int) -> Bool {
  let len = raw.length()
  if start + 1 >= len {
    return false
  }
  let first = raw.code_unit_at(start).to_int()
  let second = raw.code_unit_at(start + 1).to_int()
  first == ASCII_CR && second == ASCII_LF
}

///|
fn find_char(value : String, needle : Int) -> Int? {
  let len = value.length()
  let mut idx = 0
  while idx < len {
    if value.code_unit_at(idx).to_int() == needle {
      return Some(idx)
    }
    idx = idx + 1
  }
  None
}

///|
fn slice(value : String, start : Int, end : Int) -> String {
  if start >= end {
    return ""
  }
  let chars : Array[Char] = []
  let mut idx = start
  while idx < end {
    match value.code_unit_at(idx).to_char() {
      Some(ch) => chars.push(ch)
      None => ()
    }
    idx = idx + 1
  }
  String::from_array(chars)
}

///|
fn is_ascii_space(unit : Int) -> Bool {
  unit == ASCII_SPACE ||
  unit == ASCII_TAB ||
  unit == ASCII_CR ||
  unit == ASCII_LF
}

///|
fn starts_with_http(line : String) -> Bool {
  if line.length() < 5 {
    return false
  }
  let first = line.code_unit_at(0).to_int()
  let second = line.code_unit_at(1).to_int()
  let third = line.code_unit_at(2).to_int()
  let fourth = line.code_unit_at(3).to_int()
  let slash = line.code_unit_at(4).to_int()
  if to_ascii_upper(first) != 'H' {
    return false
  }
  if to_ascii_upper(second) != 'T' {
    return false
  }
  if to_ascii_upper(third) != 'T' {
    return false
  }
  if to_ascii_upper(fourth) != 'P' {
    return false
  }
  slash == '/'
}

///|
fn to_ascii_upper(unit : Int) -> Int {
  if unit >= ASCII_LOWER_A && unit <= ASCII_LOWER_Z {
    unit - ASCII_CASE_OFFSET
  } else {
    unit
  }
}
