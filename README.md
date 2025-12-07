# HTTP Parser (MoonBit)

## 概览

一个用 MoonBit 实现的 HTTP 报文解析器，既可以作为库被其它包直接调用，也可以通过命令行工具在本地解析抓到的原始请求或响应。项目为教学/练习用途构建，强调可读性、完整错误提示以及独立可运行的示例。

## 功能亮点

- 支持按 HTTP/1.x 规则解析完整的请求、响应或自动识别的报文 (`parse_request` / `parse_response` / `parse_message`).
- 公开 `HttpRequest`、`HttpResponse`、`HttpVersion` 等结构体，便于在上层程序中做二次处理或断言。
- 详细的错误分类 (`HttpParserError`)，可区分空报文、状态行异常、非法头部、主体长度不足、未知 Transfer-Encoding 等情形。
- 提供 `header_value` 帮助函数，简化大小写无关的头部查找。
- 自带命令行入口，支持从文件或命令行直接输入原始 HTTP 报文并打印结构化结果。

## 项目结构

```
src/
	lib/       # 解析核心逻辑 (导出 types + parse APIs)
	main/      # 提供 CLI 入口
	test/      # 白盒测试，覆盖成功/失败路径
moon.pkg.json  # 包定义及依赖
moon.mod.json  # 模块定义
```

## 库用法

```moonbit
using @http_parser {
	parse_message,
	parse_request,
	parse_response,
	header_value,
	type HttpMessage,
	type HttpRequest,
	type HttpResponse,
	type HttpParserError,
}

match parse_message(raw_text) {
	Ok(HttpMessage::Request(req)) => {
		// TODO: 根据 req.target / req.headers 做处理
	}
	Ok(HttpMessage::Response(resp)) => {
		// TODO: 根据 resp.status_code / resp.body 做处理
	}
	Err(err) => {
		println("parse failed: " + err.to_string())
	}
}
```

### 解析结果 API

- `HttpRequest`: `verb`, `target`, `version`, `headers`, `body`。
- `HttpResponse`: `version`, `status_code`, `reason`, `headers`, `body`。
- `header_value(headers, name)`: 返回大小写无关匹配的首个值 (`String?`)。

### 错误分类

`HttpParserError` 覆盖以下核心情况：

- `EmptyMessage`, `MissingHeaderBodyBoundary`：基本格式问题。
- `MissingRequestLine`, `MissingResponseLine`, `Invalid*Line`：首行或头部格式错误。
- `InvalidHttpVersion`, `InvalidStatusCode`, `InvalidContentLength`：数值解析失败。
- `IncompleteBody(expected, actual)`：`Content-Length` 与实际主体长度不符。
- `UnsupportedTransferEncoding(value)`：当前仅支持 identity 传输编码。

## 命令行工具

项目自带 CLI，可解析本地抓到的原始 HTTP 报文：

```pwsh
# 从文件读取 (推荐先用 curl.exe -i 或抓包工具保存原始字节)
moon run src/main -- --file "C:\path\to\raw_http.txt"

# 直接传入文本 (注意在 PowerShell 中添加 -- 防止 Moon 截获参数)
moon run src/main -- --inline "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"

# 兼容路径简写：
moon run src/main -- "C:\path\to\raw_http.txt"
```

解析结果会打印请求或响应的基本信息、所有头部以及主体内容。若输入的文件是 UTF-16（如 PowerShell 重定向默认行为），请改用 `cmd /c "curl.exe -i ... > raw_http.txt"` 或 `Out-File -Encoding ascii` 以保留正确的 `\r\n` 边界。

## 测试

运行项目内的白盒测试：

```pwsh
moon test
```

测试覆盖：

- 请求/响应的基础解析路径。
- 主体长度不足时的 `IncompleteBody` 错误。
- 非支持的 `Transfer-Encoding` 的报错。