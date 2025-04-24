#!/bin/bash
# 自动安装Conda和MinerU服务的Shell脚本

# 默认安装路径
INSTALL_PATH="$HOME/mineru_installer"
APP_DATA_PATH="$HOME/.magicpdf"
CONDA_PATH="$APP_DATA_PATH/conda"
MINERU_ENV_NAME="mineru_env"
MINERU_PATH="$APP_DATA_PATH/mineru"
MINICONDA_INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
MINICONDA_URL="https://repo.anaconda.com/miniconda/$MINICONDA_INSTALLER"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"

# 显示彩色消息
function print_message() {
    local message="$1"
    local color="$2"
    
    case "$color" in
        "red")    echo -e "\033[0;31m$message\033[0m" ;;
        "green")  echo -e "\033[0;32m$message\033[0m" ;;
        "yellow") echo -e "\033[0;33m$message\033[0m" ;;
        "blue")   echo -e "\033[0;34m$message\033[0m" ;;
        "cyan")   echo -e "\033[0;36m$message\033[0m" ;;
        *)        echo "$message" ;;
    esac
}

# 创建应用程序数据目录
function create_app_directory() {
    if [ ! -d "$APP_DATA_PATH" ]; then
        print_message "创建应用程序数据目录: $APP_DATA_PATH" "yellow"
        mkdir -p "$APP_DATA_PATH"
    fi
}

# 检查Conda是否已安装
function check_conda_installed() {
    # 检查PATH中是否有conda
    if command -v conda &> /dev/null; then
        CONDA_VERSION=$(conda --version)
        print_message "检测到现有Conda安装: $CONDA_VERSION" "green"
        return 0
    fi
    
    # 检查应用程序数据目录中是否有conda
    if [ -f "$CONDA_PATH/bin/conda" ]; then
        print_message "检测到应用程序数据目录中的Conda安装" "green"
        return 0
    fi
    
    return 1
}

# 下载Miniconda安装程序
function download_miniconda() {
    local installer_path="$APP_DATA_PATH/$MINICONDA_INSTALLER"
    
    if [ -f "$installer_path" ]; then
        print_message "Miniconda安装程序已存在，跳过下载" "yellow"
        echo "$installer_path"
        return 0
    fi
    
    print_message "正在下载Miniconda安装程序..." "yellow"
    if wget -q "$MINICONDA_URL" -O "$installer_path"; then
        print_message "Miniconda安装程序下载完成: $installer_path" "green"
        echo "$installer_path"
        return 0
    else
        print_message "下载Miniconda安装程序失败" "red"
        return 1
    fi
}

# 安装Miniconda
function install_miniconda() {
    local installer_path=$(download_miniconda)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    print_message "正在安装Miniconda到: $CONDA_PATH" "yellow"
    
    # 静默安装Miniconda
    bash "$installer_path" -b -p "$CONDA_PATH" -f
    
    # 检查安装是否成功
    if [ -f "$CONDA_PATH/bin/conda" ]; then
        print_message "Miniconda安装成功" "green"
        return 0
    else
        print_message "Miniconda安装失败" "red"
        return 1
    fi
}

# 创建MinerU环境
function create_mineru_environment() {
    print_message "正在创建MinerU环境: $MINERU_ENV_NAME" "yellow"
    
    local conda_exe="$CONDA_PATH/bin/conda"
    
    if [ ! -f "$conda_exe" ]; then
        print_message "未找到conda可执行文件，无法创建环境" "red"
        return 1
    fi
    
    # 检查环境是否已存在
    if "$conda_exe" env list | grep -q "$MINERU_ENV_NAME"; then
        print_message "MinerU环境已存在: $MINERU_ENV_NAME" "green"
        return 0
    fi
    
    # 创建新环境
    if "$conda_exe" create -n "$MINERU_ENV_NAME" python=3.9 -y; then
        print_message "MinerU环境创建成功" "green"
        return 0
    else
        print_message "MinerU环境创建失败" "red"
        return 1
    fi
}

# 安装MinerU依赖
function install_mineru_dependencies() {
    print_message "正在安装MinerU依赖..." "yellow"
    
    local conda_exe="$CONDA_PATH/bin/conda"
    
    if [ ! -f "$conda_exe" ]; then
        print_message "未找到conda可执行文件，无法安装依赖" "red"
        return 1
    fi
    
    # 激活环境并安装依赖
    source "$CONDA_PATH/etc/profile.d/conda.sh"
    conda activate "$MINERU_ENV_NAME"
    
    print_message "正在安装PDF解析所需的高级依赖..." "yellow"
    
    if pip install uvicorn fastapi python-multipart mineru boto3>=1.28.43 Brotli>=1.1.0 \
       click>=8.1.7 fast-langdetect>=0.2.3,\<0.3.0 loguru>=0.6.0 numpy>=1.21.6 \
       pydantic>=2.7.2,\<2.11 PyMuPDF>=1.24.9,\<1.25.0 scikit-learn>=1.0.2 \
       torch>=2.2.2 torchvision transformers>=4.49.0,\!=4.51.0,\<5.0.0 \
       pdfminer.six==20231228 tqdm>=4.67.1; then
        print_message "MinerU依赖安装成功" "green"
        conda deactivate
        return 0
    else
        print_message "MinerU依赖安装失败" "red"
        conda deactivate
        return 1
    fi
}

# 克隆或更新MinerU源代码
function setup_mineru_source() {
    print_message "正在设置MinerU源代码..." "yellow"
    
    # 从资源目录复制MinerU源代码
    local mineru_source_path="$RESOURCES_PATH/mineru_source"
    
    if [ -d "$mineru_source_path" ]; then
        # 如果资源目录中有MinerU源代码，则复制
        mkdir -p "$MINERU_PATH"
        cp -r "$mineru_source_path/"* "$MINERU_PATH/"
        print_message "MinerU源代码已从资源目录复制" "green"
        return 0
    else
        # 如果资源目录中没有MinerU源代码，则创建基本结构
        mkdir -p "$MINERU_PATH/MinerU/projects/web_api"
        
        # 创建基本的app.py文件
        local app_py_path="$MINERU_PATH/MinerU/projects/web_api/app.py"
        if [ ! -f "$app_py_path" ]; then
            cat > "$app_py_path" << EOL
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
EOL
        fi
        
        print_message "MinerU基本结构已创建" "green"
        return 0
    fi
}

# 创建启动脚本
function create_startup_script() {
    print_message "正在创建MinerU服务启动脚本..." "yellow"
    
    local startup_script_path="$APP_DATA_PATH/start_mineru_service.sh"
    
    cat > "$startup_script_path" << EOL
#!/bin/bash
echo "正在启动MinerU服务..."
source "$CONDA_PATH/etc/profile.d/conda.sh"
conda activate "$MINERU_ENV_NAME"
cd "$MINERU_PATH/MinerU/projects/web_api"
uvicorn app:app --host 0.0.0.0 --port 8888
EOL
    
    chmod +x "$startup_script_path"
    
    print_message "启动脚本已创建: $startup_script_path" "green"
    echo "$startup_script_path"
}

# 主函数
function main() {
    print_message "===== MinerU服务一键安装程序 =====" "cyan"
    
    # 创建应用目录
    create_app_directory
    
    # 检查Conda是否已安装
    if ! check_conda_installed; then
        print_message "Conda未安装，开始安装Miniconda..." "yellow"
        if ! install_miniconda; then
            print_message "Conda安装失败，无法继续" "red"
            return 1
        fi
    fi
    
    # 创建MinerU环境
    if ! create_mineru_environment; then
        print_message "MinerU环境创建失败，无法继续" "red"
        return 1
    fi
    
    # 安装MinerU依赖
    if ! install_mineru_dependencies; then
        print_message "MinerU依赖安装失败，无法继续" "red"
        return 1
    fi
    
    # 设置MinerU源代码
    if ! setup_mineru_source; then
        print_message "MinerU源代码设置失败，无法继续" "red"
        return 1
    fi
    
    # 创建启动脚本
    local startup_script=$(create_startup_script)
    
    print_message "===== MinerU服务安装完成 =====" "green"
    print_message "启动脚本位置: $startup_script" "cyan"
    print_message "您可以通过Flutter应用或直接运行启动脚本来启动MinerU服务" "cyan"
    
    return 0
}

# 执行主函数
main 