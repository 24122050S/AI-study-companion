import os
import json
from dotenv import load_dotenv
from groq import Groq 
from supabase import create_client, Client
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS

load_dotenv()

# ================= CẤU HÌNH HỆ THỐNG & VECTOR DB =================
VECTOR_DB_ROOT = "vector_db"

print("Đang khởi tạo mô hình nhúng văn bản...")
embeddings = HuggingFaceEmbeddings(model_name="keepitreal/vietnamese-sbert") 
text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=100)

print("Đang đồng bộ hóa cơ sở dữ liệu Supabase Cloud...")
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# ================= CẤU HÌNH GROQ AI =================
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "") 
groq_client = Groq(api_key=GROQ_API_KEY)
GROQ_MODEL = "llama-3.3-70b-versatile" 

# ================= HÀM TIỆN ÍCH DÙNG CHUNG =================
def call_groq(prompt: str, is_chat_mode: bool = False, temp: float = 0.2):
    try:
        sys_msg = (
            "Bạn là một Giáo sư đại học uyên bác. BẮT BUỘC TRẢ LỜI DÀI, CHI TIẾT VÀ SÂU SẮC NHẤT CÓ THỂ. "
            if is_chat_mode else
            "Bạn là AI tạo dữ liệu. Tuân thủ tuyệt đối định dạng JSON được yêu cầu, KHÔNG giải thích dông dài."
        )
        chat_completion = groq_client.chat.completions.create(
            messages=[{"role": "system", "content": sys_msg}, {"role": "user", "content": prompt}],
            model=GROQ_MODEL,
            temperature=temp, 
            max_tokens=6000, # Nâng giới hạn token để chống lỗi đứt đoạn khi sinh JSON
        )
        return chat_completion.choices[0].message.content
    except Exception as e:
        raise Exception(f"Lỗi API Groq: {str(e)}")

def extract_json_array(parsed_json, required_keys):
    result = []
    if isinstance(parsed_json, list): result = parsed_json
    elif isinstance(parsed_json, dict):
        for val in parsed_json.values():
            if isinstance(val, list):
                result = val
                break
        if not result: result = [parsed_json]
    
    valid_items = []
    for item in result:
        if isinstance(item, dict) and all(key in item for key in required_keys):
            valid_items.append(item)
    if not valid_items: raise ValueError("Dữ liệu rỗng hoặc sai cấu trúc")
    return valid_items

# ================= HÀM LẤY NGỮ CẢNH RAG =================
def get_active_context(query: str, user_id: str, notebook_id: str, k_needed: int = 15, return_refs: bool = False):
    user_vector_path = os.path.join(VECTOR_DB_ROOT, str(user_id), str(notebook_id))
    
    if not os.path.exists(os.path.join(user_vector_path, "index.faiss")): 
        return ("", []) if return_refs else ""
        
    vector_db = FAISS.load_local(user_vector_path, embeddings, allow_dangerous_deserialization=True)
    docs_and_scores = vector_db.similarity_search_with_score(query, k=50) 
    
    try:
        res = supabase.table("uploaded_files").select("filename").eq("user_id", str(user_id)).eq("notebook_id", int(notebook_id)).execute()
        active_files = [r['filename'] for r in res.data]
    except: 
        active_files = []
        
    if not active_files: 
        return ("", []) if return_refs else ""
        
    valid_docs = []
    L2_THRESHOLD = 1.6 
    
    # 🚀 LÀN ƯU TIÊN (VIP LANE): Nhận diện các câu hỏi tổng quát
    query_lower = query.lower()
    is_meta_query = any(kw in query_lower for kw in ["tóm tắt", "tổng quan", "nội dung", "ý chính", "file này", "tài liệu", "là gì"])
    
    for doc, score in docs_and_scores:
        if doc.metadata.get("filename") in active_files:
            if return_refs:
                # Nếu là câu hỏi tóm tắt, cho phép đi qua rào chắn luôn
                if is_meta_query or score <= L2_THRESHOLD:
                    valid_docs.append(doc)
            else:
                valid_docs.append(doc)
            
    if not valid_docs:
        return ("", []) if return_refs else ""
    
    formatted_contexts = []
    source_map = []
    
    for i, doc in enumerate(valid_docs[:k_needed]):
        fname = doc.metadata.get("filename", "Không rõ tài liệu")
        page = doc.metadata.get("page", "?")
        source_id = i + 1 
        
        chunk_id = doc.metadata.get("chunk_id", f"chk_{notebook_id}_{source_id}_{i}")
        
        formatted_contexts.append(f"--- NGUỒN [{source_id}] ---\nTài liệu: {fname} (Trang {page})\nNội dung: {doc.page_content}")
        
        source_map.append({
            "id": source_id,
            "file": fname,
            "page": page,
            "chunk_id": chunk_id
        })
        
    context_str = "\n\n".join(formatted_contexts)
    
    if return_refs:
        return context_str, source_map 
    return context_str