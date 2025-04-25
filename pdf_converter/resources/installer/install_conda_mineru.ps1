# 自动安装Conda和MinerU服务的PowerShell脚本
param (
    [string]$installPath = "$env:USERPROFILE\mineru_installer"
)

$ErrorActionPreference = "Stop"
$appDataPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, "MagicPDF")
$condaPath = [System.IO.Path]::Combine($appDataPath, "conda")
$mineruEnvName = "mineru_env"
$mineruPath = [System.IO.Path]::Combine($appDataPath, "MinerU")
$minicondaInstaller = "Miniconda3-latest-Windows-x86_64.exe"
$minicondaUrl = "https://repo.anaconda.com/miniconda/$minicondaInstaller"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$resourcesPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($scriptPath, ".."))

# 输出带颜色的消息
function Write-ColorMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor = "White"
    )
    
    Write-Host $Message -ForegroundColor $ForegroundColor
}

# 创建应用程序数据目录
function New-AppDirectory {
    if (-not (Test-Path $appDataPath)) {
        Write-ColorMessage "创建应用程序数据目录: $appDataPath" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $appDataPath -Force | Out-Null
    }
}

# 检查Conda是否已安装
function Test-CondaInstalled {
    try {
        # 检查环境变量中是否有conda
        $condaCommand = Get-Command conda -ErrorAction SilentlyContinue
        if ($condaCommand) {
            $condaVersion = conda --version
            Write-ColorMessage "检测到现有Conda安装: $condaVersion" -ForegroundColor Green
            return $true
        }
        
        # 检查应用程序数据目录中是否有conda
        $condaExe = [System.IO.Path]::Combine($condaPath, "Scripts", "conda.exe")
        if (Test-Path $condaExe) {
            Write-ColorMessage "检测到应用程序数据目录中的Conda安装" -ForegroundColor Green
            return $true
        }
        
        return $false
    }
    catch {
        return $false
    }
}

# 下载Miniconda安装程序
function Get-Miniconda {
    $installerPath = [System.IO.Path]::Combine($appDataPath, $minicondaInstaller)
    
    if (Test-Path $installerPath) {
        Write-ColorMessage "Miniconda安装程序已存在，跳过下载" -ForegroundColor Yellow
        return $installerPath
    }
    
    Write-ColorMessage "正在下载Miniconda安装程序..." -ForegroundColor Yellow
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($minicondaUrl, $installerPath)
        Write-ColorMessage "Miniconda安装程序下载完成: $installerPath" -ForegroundColor Green
        return $installerPath
    }
    catch {
        Write-ColorMessage "下载Miniconda安装程序失败: $_" -ForegroundColor Red
        throw
    }
}

# 安装Miniconda
function Install-Miniconda {
    $installerPath = Get-Miniconda
    
    Write-ColorMessage "正在安装Miniconda到: $condaPath" -ForegroundColor Yellow
    try {
        # 静默安装Miniconda
        $installArgs = "/S /RegisterPython=0 /AddToPath=0 /D=$condaPath"
        Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait
        
        # 检查安装是否成功
        $condaExe = [System.IO.Path]::Combine($condaPath, "Scripts", "conda.exe")
        if (Test-Path $condaExe) {
            Write-ColorMessage "Miniconda安装成功" -ForegroundColor Green
            return $true
        }
        else {
            Write-ColorMessage "Miniconda安装失败" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-ColorMessage "安装Miniconda时出错: $_" -ForegroundColor Red
        return $false
    }
}

# 创建MinerU环境
function New-MineruEnvironment {
    Write-ColorMessage "正在创建MinerU环境: $mineruEnvName" -ForegroundColor Yellow
    
    $condaExe = [System.IO.Path]::Combine($condaPath, "Scripts", "conda.exe")
    
    if (-not (Test-Path $condaExe)) {
        Write-ColorMessage "未找到conda.exe，无法创建环境" -ForegroundColor Red
        return $false
    }
    
    try {
        # 检查环境是否已存在
        $envList = & $condaExe env list
        if ($envList -match $mineruEnvName) {
            Write-ColorMessage "MinerU环境已存在: $mineruEnvName" -ForegroundColor Green
            return $true
        }
        
        # 创建新环境
        & $condaExe create -n $mineruEnvName python=3.9 -y
        if ($LASTEXITCODE -eq 0) {
            Write-ColorMessage "MinerU环境创建成功" -ForegroundColor Green
            return $true
        }
        else {
            Write-ColorMessage "MinerU环境创建失败" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-ColorMessage "创建MinerU环境时出错: $_" -ForegroundColor Red
        return $false
    }
}

# 安装MinerU依赖
function Install-MineruDependencies {
    Write-ColorMessage "正在安装MinerU依赖..." -ForegroundColor Yellow
    
    $condaExe = [System.IO.Path]::Combine($condaPath, "Scripts", "conda.exe")
    $activateScript = [System.IO.Path]::Combine($condaPath, "Scripts", "activate.bat")
    
    if (-not (Test-Path $condaExe) -or -not (Test-Path $activateScript)) {
        Write-ColorMessage "未找到conda或activate脚本，无法安装依赖" -ForegroundColor Red
        return $false
    }
    
    try {
        # 激活环境并安装依赖
        $installCmd = "call `"$activateScript`" $mineruEnvName && " + 
                     "pip install uvicorn fastapi python-multipart mineru boto3>=1.28.43 Brotli>=1.1.0 " + 
                     "click>=8.1.7 fast-langdetect>=0.2.3,<0.3.0 loguru>=0.6.0 numpy>=1.21.6 " + 
                     "pydantic>=2.7.2,<2.11 PyMuPDF>=1.24.9,<1.25.0 scikit-learn>=1.0.2 " + 
                     "torch>=2.2.2 torchvision transformers>=4.49.0,!=4.51.0,<5.0.0 " + 
                     "pdfminer.six==20231228 tqdm>=4.67.1 && pip install mineru"
                     
        Write-ColorMessage "正在安装PDF解析所需的高级依赖及MinerU核心包..." -ForegroundColor Yellow
        $result = Start-Process cmd.exe -ArgumentList "/c $installCmd" -Wait -PassThru -NoNewWindow
        
        if ($result.ExitCode -eq 0) {
            Write-ColorMessage "MinerU依赖安装成功" -ForegroundColor Green
            return $true
        }
        else {
            Write-ColorMessage "MinerU依赖安装失败" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-ColorMessage "安装MinerU依赖时出错: $_" -ForegroundColor Red
        return $false
    }
}

# 克隆或更新MinerU源代码
function Initialize-MineruSource {
    Write-ColorMessage "正在设置MinerU源代码..." -ForegroundColor Yellow
    
    # 从资源目录复制MinerU源代码
    $mineruSourcePath = [System.IO.Path]::Combine($resourcesPath, "mineru_source")
    
    if (Test-Path $mineruSourcePath) {
        # 如果资源目录中有MinerU源代码，则复制
        if (-not (Test-Path $mineruPath)) {
            New-Item -ItemType Directory -Path $mineruPath -Force | Out-Null
        }
        
        Copy-Item -Path "$mineruSourcePath\*" -Destination $mineruPath -Recurse -Force
        Write-ColorMessage "MinerU源代码已从资源目录复制" -ForegroundColor Green
        return $true
    }
    else {
        # 如果资源目录中没有MinerU源代码，则创建基本结构
        if (-not (Test-Path $mineruPath)) {
            New-Item -ItemType Directory -Path $mineruPath -Force | Out-Null
        }
        
        $webApiPath = [System.IO.Path]::Combine($mineruPath, "MinerU", "projects", "web_api")
        if (-not (Test-Path $webApiPath)) {
            New-Item -ItemType Directory -Path $webApiPath -Force | Out-Null
        }
        
        # 创建基本的app.py文件
        $appPyPath = [System.IO.Path]::Combine($webApiPath, "app.py")
        if (-not (Test-Path $appPyPath)) {
            @"
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse
import uvicorn

app = FastAPI()

@app.get("/ping")
def ping():
    return {"status": "ok"}

@app.post("/file_parse")
async def file_parse(file: UploadFile = File(...), return_content_list: bool = Form(False)):
    try:
        # 简单示例，实际应用中需要集成真正的PDF解析功能
        content = f"这是从 {file.filename} 中提取的内容示例。实际应用需要集成完整的MinerU功能。"
        return {"content_list": [content], "status": "success"}
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"message": f"处理文件时出错: {str(e)}"}
        )

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8888)
"@ | Out-File -FilePath $appPyPath -Encoding utf8
        }
        
        Write-ColorMessage "MinerU基本结构已创建" -ForegroundColor Green
        return $true
    }
}

# 创建启动脚本
function New-StartupScript {
    Write-ColorMessage "正在创建MinerU服务启动脚本..." -ForegroundColor Yellow
    
    $startupScriptPath = [System.IO.Path]::Combine($appDataPath, "start_mineru_service.bat")
    $activateScript = [System.IO.Path]::Combine($condaPath, "Scripts", "activate.bat")
    $webApiPath = [System.IO.Path]::Combine($mineruPath, "MinerU", "projects", "web_api")
    
    @"
@echo off
echo 正在启动MinerU服务...
call "$activateScript" $mineruEnvName
cd /d "$webApiPath"
uvicorn app:app --host 0.0.0.0 --port 8888
"@ | Out-File -FilePath $startupScriptPath -Encoding ascii
    
    Write-ColorMessage "启动脚本已创建: $startupScriptPath" -ForegroundColor Green
    return $startupScriptPath
}

# 主函数
function Main {
    Write-ColorMessage "===== MinerU服务一键安装程序 =====" -ForegroundColor Cyan
    
    # 创建应用目录
    New-AppDirectory
    
    # 检查Conda是否已安装
    $condaInstalled = Test-CondaInstalled
    if (-not $condaInstalled) {
        Write-ColorMessage "Conda未安装，开始安装Miniconda..." -ForegroundColor Yellow
        $condaInstalled = Install-Miniconda
        if (-not $condaInstalled) {
            Write-ColorMessage "Conda安装失败，无法继续" -ForegroundColor Red
            return $false
        }
    }
    
    # 创建MinerU环境
    $envCreated = New-MineruEnvironment
    if (-not $envCreated) {
        Write-ColorMessage "MinerU环境创建失败，无法继续" -ForegroundColor Red
        return $false
    }
    
    # 安装MinerU依赖
    $depsInstalled = Install-MineruDependencies
    if (-not $depsInstalled) {
        Write-ColorMessage "MinerU依赖安装失败，无法继续" -ForegroundColor Red
        return $false
    }
    
    # 设置MinerU源代码
    $sourceSetup = Initialize-MineruSource
    if (-not $sourceSetup) {
        Write-ColorMessage "MinerU源代码设置失败，无法继续" -ForegroundColor Red
        return $false
    }
    
    # 创建启动脚本
    $startupScript = New-StartupScript
    
    Write-ColorMessage "===== MinerU服务安装完成 =====" -ForegroundColor Green
    Write-ColorMessage "启动脚本位置: $startupScript" -ForegroundColor Cyan
    Write-ColorMessage "您可以通过Flutter应用或直接运行启动脚本来启动MinerU服务" -ForegroundColor Cyan
    
    return $true
}

# 执行主函数
Main 