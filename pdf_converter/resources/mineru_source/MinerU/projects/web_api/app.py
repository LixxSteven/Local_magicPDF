from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import io
import logging
import tempfile
import os
from typing import List, Optional

# 导入PDF处理相关依赖 (旧)
# import fitz  # PyMuPDF
# import pdfminer.high_level
# from langdetect import detect_langs

# --- 新增 MinerU 依赖 ---
from magic_pdf.pipe.pipeline_factory import Pipeline
from magic_pdf.libs.MakeContent import MakeContent
from magic_pdf.model.doc_analyze_by_custom_model import doc_analyze
from magic_pdf.data.doc_data import DocData
from magic_pdf.rw.AbsReaderWriter import AbsReaderWriter

# 定义一个用于MinerU的文件写入器
class SimpleFileWriter(AbsReaderWriter):
    def __init__(self, output_dir):
        self.output_dir = output_dir
        os.makedirs(self.output_dir, exist_ok=True)

    def save(self, content_to_save: bytes | str, target_path: str) -> bool:
        full_path = os.path.join(self.output_dir, target_path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        mode = 'wb' if isinstance(content_to_save, bytes) else 'w'
        encoding = None if isinstance(content_to_save, bytes) else 'utf-8'
        try:
            with open(full_path, mode, encoding=encoding) as f:
                f.write(content_to_save)
            return True
        except Exception as e:
            logger.error(f"Failed to save file {full_path}: {e}")
            return False

    def read(self, file_path: str) -> bytes:
        # 这个示例主要用于写入，读取可以按需实现
        raise NotImplementedError("Read operation not implemented in SimpleFileWriter")
# --- 结束新增 ---

app = FastAPI()

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("mineru_api")

# 添加CORS中间件
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 允许所有来源，生产环境中应限制
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/ping")
def ping():
    """健康检查接口"""
    return {"status": "ok"}

@app.post("/file_parse")
async def file_parse(
    file: UploadFile = File(...), 
    return_content_list: bool = Form(False), # 此参数现在可能意义不大，因为返回格式由output_format控制
    # --- 新增高级选项参数 ---
    extract_images: bool = Form(True),
    preserve_layout: bool = Form(True), # 注意：MinerU本身是否支持此选项需确认
    output_format: str = Form("markdown"), # 支持 markdown, html, json
    detect_language: bool = Form(True), # 注意：MinerU本身是否支持此选项需确认
    support_tables: bool = Form(True) # 注意：MinerU本身是否支持此选项需确认
    # --- 结束新增 ---
): 
    """
    增强版PDF文件解析接口，使用完整MinerU库
    """
    try:
        logger.info(f"接收到文件解析请求: {file.filename}, 输出格式: {output_format}")
        
        contents = await file.read()
        
        # 使用临时目录处理
        with tempfile.TemporaryDirectory() as temp_dir:
            pdf_temp_path = os.path.join(temp_dir, file.filename)
            with open(pdf_temp_path, 'wb') as f:
                f.write(contents)
                
            logger.info(f"PDF文件已保存到临时路径: {pdf_temp_path}")

            # 初始化MinerU DocData
            doc_data = DocData(pdf_temp_path)
            
            # 初始化写入器
            image_dir = os.path.join(temp_dir, "images")
            image_writer = SimpleFileWriter(image_dir) if extract_images else None
            md_writer = SimpleFileWriter(temp_dir)

            # 构建MinerU参数
            model_params = {}
            pipeline_params = {
                "output_image_dir": "images" if extract_images else None,
                # 注意：根据MinerU实际API调整参数名和值
                # "preserve_layout": preserve_layout, 
                # "detect_language": detect_language,
                # "support_tables": support_tables,
            }

            # 执行文档分析
            logger.info("开始执行MinerU文档分析...")
            model_out = doc_analyze(doc_data.get_doc_path(), doc_data, **model_params)
            logger.info("MinerU文档分析完成")

            # 创建Pipeline
            # 注意：这里假设使用默认的txt模式Pipeline，如需OCR模式需要判断
            # 需要根据MinerU最新文档确认Pipeline名称和初始化方式
            try:
                # 尝试使用标准Pipeline名称
                pipe = Pipeline("TxtPipeLine", model_out, image_writer, pipeline_params)
            except Exception as pipe_err:
                logger.error(f"无法初始化Pipeline 'TxtPipeLine': {pipe_err}")
                # 这里可以尝试回退到其他Pipeline或抛出错误
                raise

            # 执行Pipeline
            logger.info("开始执行MinerU Pipeline...")
            pipe.do() 
            logger.info("MinerU Pipeline执行完成")
            
            # 获取结果
            maker = MakeContent(pipe.get_pipe_result())
            result = ""
            if output_format == 'markdown':
                logger.info("生成Markdown格式结果...")
                result = maker.to_markdown(pipeline_params.get("output_image_dir"))
            elif output_format == 'html':
                logger.info("生成HTML格式结果...")
                # 注意：MinerU的MakeContent可能没有直接的to_html，需要查阅文档或自行实现
                # result = maker.to_html(pipeline_params.get("output_image_dir")) 
                result = f"<html><body><h1>HTML output not yet fully implemented in API</h1><pre>{maker.to_markdown(pipeline_params.get("output_image_dir"))}</pre></body></html>" # 临时替代
            elif output_format == 'json':
                logger.info("生成JSON格式结果...")
                result = maker.to_json()
            else:
                logger.warning(f"不支持的输出格式: {output_format}, 将默认输出Markdown")
                result = maker.to_markdown(pipeline_params.get("output_image_dir"))
                
            logger.info(f"文件 {file.filename} 解析完成，输出格式: {output_format}")
            
            return {
                "result": result, 
                "status": "success"
            }

    except Exception as e:
        logger.error(f"处理文件 {file.filename} 时出错: {str(e)}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"message": f"处理文件时出错: {str(e)}", "status": "error"}
        )

# --- 移除旧的提取函数 ---
# def extract_text_with_pymupdf(pdf_path: str) -> List[str]:
#     ...
# 
# def extract_text_with_pdfminer(pdf_path: str) -> List[str]:
#     ...
# --- 结束移除 ---

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8888) 