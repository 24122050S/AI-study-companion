from fastapi import APIRouter, UploadFile, File, Form, HTTPException
import os
import shutil
import fitz
import docx
from pptx import Presentation
import pytesseract
from PIL import Image
import io
from core import supabase, embeddings, text_splitter, VECTOR_DB_ROOT, call_groq
from langchain_community.vectorstores import FAISS

pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'

router = APIRouter()

@router.post("/api/upload")
async def upload_file(file: UploadFile = File(...), user_id: str = Form(...), notebook_id: str = Form(...)): 
    try:
        content = await file.read()
        ext = file.filename.split('.')[-1].lower()
        chunks, metadatas = [], []
        
        if ext == 'pdf':
            pdf_document = fitz.open(stream=content, filetype="pdf")
            for page_num in range(len(pdf_document)):
                page = pdf_document.load_page(page_num)
                extracted = page.get_text("text") 
                if extracted.strip():
                    page_chunks = text_splitter.split_text(extracted)
                    chunks.extend(page_chunks)
                    metadatas.extend([{"filename": file.filename, "page": page_num + 1} for _ in page_chunks])
        elif ext == 'txt':
            text = content.decode('utf-8', errors='ignore')
            if text.strip():
                page_chunks = text_splitter.split_text(text)
                chunks.extend(page_chunks)
                metadatas.extend([{"filename": file.filename, "page": 1} for _ in page_chunks])
        else: 
            raise HTTPException(status_code=400, detail=f"Định dạng .{ext} chưa được hỗ trợ!")

        if not chunks: return {"status": "error", "message": "File rỗng hoặc không có chữ!"}

        # 🛡️ ĐÃ BỌC THÉP ÉP KIỂU str()
        user_vector_path = os.path.join(VECTOR_DB_ROOT, str(user_id), str(notebook_id))
        
        if os.path.exists(user_vector_path):
            vector_db = FAISS.load_local(user_vector_path, embeddings, allow_dangerous_deserialization=True)
            vector_db.add_texts(chunks, metadatas=metadatas) 
        else:
            vector_db = FAISS.from_texts(chunks, embeddings, metadatas=metadatas) 
        vector_db.save_local(user_vector_path)

        # 🛡️ Ghi vào Database
        supabase.table("uploaded_files").insert({"user_id": user_id, "filename": file.filename, "notebook_id": int(notebook_id)}).execute()
        return {"status": "success", "message": f"AI đã học xong file {file.filename}!"}
    except Exception as e: 
        print(f"🔥 [LỖI UPLOAD CRITICAL]: {str(e)}") # Báo lỗi cực mạnh ra Terminal
        raise HTTPException(status_code=500, detail=f"Lỗi hệ thống: {str(e)}")

@router.get("/api/files/{user_id}/{notebook_id}")
async def get_uploaded_files(user_id: str, notebook_id: int):
    res = supabase.table("uploaded_files").select("*").eq("user_id", user_id).eq("notebook_id", notebook_id).order("upload_date", desc=True).execute()
    return [{"id": r['id'], "filename": r['filename'], "date": r['upload_date']} for r in res.data]

@router.delete("/api/files/{file_id}")
async def delete_file_history(file_id: int):
    try:
        res = supabase.table("uploaded_files").select("user_id", "filename", "notebook_id").eq("id", file_id).execute()
        if not res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy tài liệu này.")
            
        user_id = res.data[0]['user_id']
        filename = res.data[0]['filename']
        notebook_id = res.data[0]['notebook_id'] 
        
        user_vector_path = os.path.join(VECTOR_DB_ROOT, str(user_id), str(notebook_id))
        if os.path.exists(user_vector_path):
            vector_db = FAISS.load_local(user_vector_path, embeddings, allow_dangerous_deserialization=True)
            ids_to_delete = [doc_id for doc_id, doc in vector_db.docstore._dict.items() if doc.metadata.get("filename") == filename]
            if ids_to_delete:
                vector_db.delete(ids_to_delete)
                if not vector_db.docstore._dict:
                    shutil.rmtree(user_vector_path)
                else:
                    vector_db.save_local(user_vector_path)
        
        supabase.table("uploaded_files").delete().eq("id", file_id).execute()
        return {"status": "success", "message": f"Đã xóa vĩnh viễn tài liệu {filename}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi hệ thống khi xóa file: {str(e)}")

@router.get("/api/reference")
async def get_reference_content(user_id: str, filename: str, page: int, notebook_id: str = ""):
    try:
        user_vector_path = os.path.join(VECTOR_DB_ROOT, str(user_id), str(notebook_id)) if notebook_id else os.path.join(VECTOR_DB_ROOT, str(user_id))
        if not os.path.exists(user_vector_path): return {"status": "error", "data": "Không tìm thấy dữ liệu học tập."}

        vector_db = FAISS.load_local(user_vector_path, embeddings, allow_dangerous_deserialization=True)
        def normalize_filename(name): return name.replace("_", "").replace(" ", "").replace("%20", "").lower()
        target_filename = normalize_filename(filename)
        
        original_chunks = [doc.page_content for doc_id, doc in vector_db.docstore._dict.items() if normalize_filename(doc.metadata.get("filename", "")) == target_filename and doc.metadata.get("page") == page]
        if not original_chunks: return {"status": "success", "data": "Không trích xuất được lý thuyết chi tiết cho trang này."}

        raw_theory = "\n\n...\n\n".join(original_chunks)
        format_prompt = f"Đây là văn bản thô. HÃY LÀM 2 VIỆC:\n1. Định dạng lại bằng Markdown (kẻ bảng, in đậm).\n2. TUYỆT ĐỐI GIỮ NGUYÊN 100% THÔNG TIN. KHÔNG THÊM BỚT CHỮ.\n\nVĂN BẢN THÔ:\n{raw_theory}"
        formatted_theory = call_groq(format_prompt, is_chat_mode=False, temp=0.1)
        return {"status": "success", "data": formatted_theory}
    except Exception as e: return {"status": "error", "data": f"Lỗi trích xuất: {str(e)}"}