# MinerU PDF解析 API

这是MinerU项目的PDF解析API服务，提供高级PDF文档解析和文本提取功能。

## 功能特点

- 支持通过REST API上传和解析PDF文件
- 高级文本提取，使用多种PDF解析库（PyMuPDF和pdfminer.six）确保最佳结果
- 自动语言检测
- 页面分析和内容结构化
- 支持批量处理和并发请求

## API端点

### 健康检查

```
GET /ping
```

返回服务状态信息。

### PDF文件解析

```
POST /file_parse
```

参数:
- `file`: PDF文件（必需，multipart/form-data）
- `return_content_list`: 布尔值，是否返回内容列表（可选，默认为false）

返回内容示例:

```json
{
  "content_list": ["页面1的内容", "页面2的内容", ...],
  "language": "zh",
  "pages": 10,
  "status": "success"
}
```

或者：

```json
{
  "result": "完整PDF内容...",
  "language": "zh",
  "pages": 10,
  "status": "success"
}
```

## 安装和运行

1. 确保已安装所有依赖：

```bash
pip install -r requirements.txt
```

2. 启动服务：

```bash
uvicorn app:app --host 0.0.0.0 --port 8888
```

3. 访问API文档：http://localhost:8888/docs

## 技术栈

- FastAPI: 高性能Web框架
- PyMuPDF: 高效PDF解析库
- pdfminer.six: 强大的PDF文本提取工具
- fast-langdetect: 快速的语言检测库

## 进阶用法

### 自定义PDF内容提取

针对不同类型的PDF文档，API采用不同的提取策略：

1. 对于文本型PDF，使用PyMuPDF直接提取文本内容
2. 对于扫描型PDF，则可能需要集成OCR功能（当前版本尚未包含OCR功能）
3. 对于复杂布局，使用pdfminer提供更好的布局分析

### 批量处理

服务支持并发请求处理，可以同时处理多个PDF文件。 