# MinerU服务启动问题修复记录

## 问题描述

用户报告在启动MinerU服务时遇到以下错误：

```
flutter: [2025-04-23 19:40:50.584] [ERROR] 启动MinerU服务时出错: Bad state: Process is detached 
flutter: [2025-04-23 19:40:54.562] [ERROR] 启动MinerU服务时出错: Bad state: Process is detached 
flutter: [2025-04-23 19:41:08.835] [ERROR] 启动MinerU服务时出错: Bad state: Process is detached 
Lost connection to device. 
```

用户需要检查MinerU本地服务的启动方式（包括激活conda环境等），并在软件UI中添加详细的错误信息显示。

## 解决方案

### 1. 修改MinerU服务启动方法

- 添加了conda环境激活支持
- 改进了错误处理机制
- 增加了详细的错误信息收集和显示

### 2. 改进UI界面

- 添加了服务状态指示器
- 增加了详细的错误信息显示区域
- 添加了MinerU服务配置帮助对话框

### 3. 添加服务状态检测

- 应用启动时自动检查服务状态
- 服务启动后定期检查服务状态
- 在UI中实时显示服务运行状态

## 技术细节

1. 在`MineruService`类中修改了`startMineruService`方法：
   - 添加了conda环境激活命令
   - 使用`inheritStdio`模式捕获进程输出
   - 添加了错误信息回调机制

2. 在UI中添加了服务状态指示器和错误信息显示区域：
   - 使用颜色区分服务运行状态（绿色表示运行中，红色表示未运行）
   - 错误信息区域提供详细的错误原因和解决建议

3. 添加了MinerU服务配置帮助对话框：
   - 提供conda环境配置步骤
   - 提供常见问题排查指南
   - 包含可复制的命令示例

## 后续建议

1. 考虑添加MinerU服务配置界面，允许用户自定义服务路径和conda环境名称
2. 添加自动修复功能，尝试自动解决常见的服务启动问题
3. 实现服务日志查看功能，方便用户排查问题