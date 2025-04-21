# PDF转换工具

这是一个基于Flutter和MinerU的PDF转换工具，可以将PDF文件转换为Markdown、DOCX和HTML格式。

## 功能特点

- 简洁的用户界面
- 支持将PDF转换为Markdown、DOCX和HTML格式
- 转换结果预览
- 一键打开转换后的文件

## 使用方法

1. 点击「选择文件」按钮选择要转换的PDF文件
2. 从下拉菜单中选择要转换的格式（Markdown、DOCX或HTML）
3. 点击「开始转换」按钮开始转换
4. 转换完成后，可以在结果区域预览转换结果（对于文本格式）或打开转换后的文件

## MinerU配置

本应用默认MinerU API运行在 `http://localhost:8000`。如果您的MinerU API运行在不同的地址，请修改 `lib/services/mineru_service.dart` 文件中的 `baseUrl` 参数。

```dart
// 修改为您的MinerU API地址
final MineruService _mineruService = MineruService(baseUrl: 'http://your-mineru-api-url');
```

## 构建Windows可执行文件

要构建Windows可执行文件，请运行以下命令：

```bash
flutter build windows
```

构建完成后，可执行文件将位于 `build/windows/runner/Release/` 目录中。
