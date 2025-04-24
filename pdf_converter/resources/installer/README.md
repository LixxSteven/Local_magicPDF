# MinerU服务安装指南

此目录包含自动安装Conda和MinerU服务的脚本，使您能够轻松地设置PDF转换所需的所有环境。

## 系统要求

- Windows 10/11 (64位) 或 Linux/macOS
- 至少2GB可用磁盘空间
- 稳定的网络连接（用于下载安装包）

## 安装方法

### Windows 用户

1. 通过应用内的"启动MinerU服务"按钮，应用会自动启动安装过程
2. 或者，右键点击 `install_conda_mineru.ps1` 文件，选择"使用PowerShell运行"
   - 如果遇到执行策略限制，可能需要以管理员身份打开PowerShell，然后执行以下命令：
     ```powershell
     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
     cd "<安装脚本所在目录>"
     .\install_conda_mineru.ps1
     ```

### Linux/macOS 用户

1. 通过应用内的"启动MinerU服务"按钮，应用会自动启动安装过程
2. 或者，打开终端，切换到安装脚本所在目录，然后执行：
   ```bash
   chmod +x install_conda_mineru.sh
   ./install_conda_mineru.sh
   ```

## 安装流程说明

安装脚本将执行以下操作：

1. 检查是否已安装Conda环境，如果没有则下载并安装Miniconda
2. 创建名为"mineru_env"的Conda环境
3. 安装MinerU服务所需的依赖（uvicorn, fastapi, python-multipart, mineru）
4. 设置MinerU服务源代码
5. 创建启动脚本

## 启动MinerU服务

安装完成后，有两种方式启动MinerU服务：

1. 通过应用内的"启动MinerU服务"按钮
2. 或者直接运行安装程序创建的启动脚本：
   - Windows: `%LOCALAPPDATA%\MagicPDF\start_mineru_service.bat`
   - Linux/macOS: `~/.magicpdf/start_mineru_service.sh`

## 故障排除

### 常见问题

1. **安装失败，提示网络错误**
   - 检查您的网络连接
   - 确保可以访问Conda下载服务器

2. **MinerU服务无法启动**
   - 检查安装日志
   - 确保端口8888未被其他应用占用

3. **PDF转换失败**
   - 确认MinerU服务正在运行
   - 检查应用日志中的详细错误信息

如果您遇到其他问题，请联系技术支持团队。 