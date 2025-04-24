# 修复 mineru_service.dart 中的脚本语法错误

## 问题描述

在 `mineru_service.dart` 文件中，嵌入的 PowerShell 和 Bash 脚本存在语法错误，主要是变量引用和字符串转义的问题。错误位于以下几个位置：

1. 第243行：PowerShell 变量 `$?` 需要在 Dart 字符串中正确转义
2. 第246行：PowerShell 变量 `$?` 需要在 Dart 字符串中正确转义
3. 第258行：PowerShell 变量 `$_.Exception.Message` 需要在 Dart 字符串中正确转义
4. 第267行：Bash 命令替换 `$(conda info --base)` 需要在 Dart 字符串中正确转义
5. 第267-269行：Bash 脚本中不必要的反斜杠转义

## 解决方案

### 1. PowerShell 脚本修复

在 PowerShell 脚本中，我们需要对特殊变量进行转义，以便 Dart 编译器能够正确解析：

- `$?` 改为 `\$?`
- `$($_.Exception.Message)` 改为 `\$(\$_.Exception.Message)`

### 2. Bash 脚本修复

在 Bash 脚本中，我们需要：

- 对命令替换语法进行转义：`$(conda info --base)` 改为 `\$(conda info --base)`
- 移除不必要的行尾反斜杠 `\`，改为普通的换行符

## 修复后的结果

修复后，`dart analyze` 命令显示没有任何语法错误，文件可以正常编译。

```
Analyzing mineru_service.dart...
No issues found!
```

这些修复确保了 MinerU 服务可以正常启动，无论是在 Windows 环境（使用 PowerShell）还是在类 Unix 环境（使用 Bash）中。