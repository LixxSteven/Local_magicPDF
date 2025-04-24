from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import io
import logging
import tempfile
import os
from typing import List, Optional

# 导入PDF处理相关依赖
import fitz  # PyMuPDF
import pdfminer.high_level
from langdetect import detect_langs

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
async def file_parse(file: UploadFile = File(...), return_content_list: bool = Form(False)):
    """
    PDF文件解析接口
    
    Args:
        file: 上传的PDF文件
        return_content_list: 是否返回提取的内容列表
        
    Returns:
        JSON响应，包含提取的内容
    """
    try:
        logger.info(f"接收到文件解析请求: {file.filename}")
        
        # 读取上传的文件
        contents = await file.read()
        
        # 使用临时文件处理PDF
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as temp_file:
            temp_file.write(contents)
            temp_file_path = temp_file.name
        
        try:
            # 使用PyMuPDF提取文本
            content_list = extract_text_with_pymupdf(temp_file_path)
            
            # 如果PyMuPDF提取结果为空，则尝试使用pdfminer
            if not content_list or all(not text.strip() for text in content_list):
                logger.info(f"PyMuPDF提取结果为空，使用pdfminer尝试提取: {file.filename}")
                content_list = extract_text_with_pdfminer(temp_file_path)
            
            # 检测语言
            lang = "unknown"
            if content_list and any(text.strip() for text in content_list):
                sample_text = " ".join(content_list[:3])  # 取前3段进行语言检测
                try:
                    lang_result = detect_langs(sample_text)
                    lang = str(lang_result[0]).split(':')[0] if lang_result else "unknown"
                except:
                    pass
            
            logger.info(f"文件 {file.filename} 解析完成，检测语言: {lang}")
            
            # 返回结果
            if return_content_list:
                return {
                    "content_list": content_list,
                    "language": lang,
                    "pages": len(content_list),
                    "status": "success"
                }
            else:
                return {
                    "result": "\n\n".join(content_list),
                    "language": lang,
                    "pages": len(content_list),
                    "status": "success"
                }
        finally:
            # 清理临时文件
            if os.path.exists(temp_file_path):
                os.unlink(temp_file_path)
                
    except Exception as e:
        logger.error(f"处理文件时出错: {str(e)}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"message": f"处理文件时出错: {str(e)}", "status": "error"}
        )

def extract_text_with_pymupdf(pdf_path: str) -> List[str]:
    """
    使用PyMuPDF提取PDF中的文本
    
    Args:
        pdf_path: PDF文件路径
        
    Returns:
        提取的文本列表，每个元素对应一页
    """
    content_list = []
    try:
        doc = fitz.open(pdf_path)
        for page in doc:
            content_list.append(page.get_text())
        doc.close()
    except Exception as e:
        logger.error(f"PyMuPDF提取文本失败: {str(e)}", exc_info=True)
    
    return content_list

def extract_text_with_pdfminer(pdf_path: str) -> List[str]:
    """
    使用pdfminer提取PDF中的文本
    
    Args:
        pdf_path: PDF文件路径
        
    Returns:
        提取的文本列表，每个元素对应一页
    """
    content_list = []
    try:
        with open(pdf_path, 'rb') as f:
            text = pdfminer.high_level.extract_text(f)
            # 简单地按页分隔，实际应用中可能需要更复杂的处理
            paragraphs = text.split('\n\n')
            content_list = [p for p in paragraphs if p.strip()]
    except Exception as e:
        logger.error(f"pdfminer提取文本失败: {str(e)}", exc_info=True)
    
    return content_list

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8888) 