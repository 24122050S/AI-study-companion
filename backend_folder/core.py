import os
import json
import random
from dotenv import load_dotenv
from groq import Groq 
from supabase import create_client, Client
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_huggingface import HuggingFaceEmbeddings

load_dotenv()

print("Đang khởi tạo mô hình nhúng văn bản...")
embeddings = HuggingFaceEmbeddings(model_name="keepitreal/vietnamese-sbert") 
text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=100)

print("Đang đồng bộ hóa cơ sở dữ liệu Supabase Cloud...")
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

GROQ_API_KEYS_STR = os.getenv("GROQ_API_KEYS", "") 
GROQ_API_KEYS = [k.strip() for k in GROQ_API_KEYS_STR.split(",") if k.strip()]
GROQ_MODEL = "llama-3.3-70b-versatile" 

def get_groq_client():
    if not GROQ_API_KEYS:
        raise Exception("Chưa cấu hình GROQ_API_KEYS trong file .env!")
    return Groq(api_key=random.choice(GROQ_API_KEYS))

def call_groq(prompt: str, is_chat_mode: bool = False, temp: float = 0.2):
    sys_msg = (
        "Bạn là một Giáo sư đại học uyên bác. BẮT BUỘC TRẢ LỜI DÀI, CHI TIẾT VÀ SÂU SẮC NHẤT CÓ THỂ. "
        if is_chat_mode else
        "Bạn là AI tạo dữ liệu. Tuân thủ tuyệt đối định dạng JSON được yêu cầu, KHÔNG giải thích dông dài."
    )
    keys_to_try = list(GROQ_API_KEYS)
    random.shuffle(keys_to_try)
    
    # 🚀 CHIẾN THUẬT ĐỔI MÔ HÌNH (HẠ CÁNH MỀM)
    models_to_try = [GROQ_MODEL, "llama3-8b-8192", "mixtral-8x7b-32768"]
    last_error = None
    
    for model in models_to_try:
        for key in keys_to_try:
            try:
                client = Groq(api_key=key)
                chat_completion = client.chat.completions.create(
                    messages=[{"role": "system", "content": sys_msg}, {"role": "user", "content": prompt}],
                    model=model,
                    temperature=temp, 
                    max_tokens=4000, 
                )
                return chat_completion.choices[0].message.content
            except Exception as e:
                last_error = e
                continue # Lỗi thì lẳng lặng thử Key tiếp theo
                
    raise Exception(f"Tất cả các API Key và Mô hình đều cạn kiệt Token! Lỗi: {last_error}")

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

# ================= HÀM LẤY NGỮ CẢNH RAG (GỌI TRỰC TIẾP RPC CHỐNG LỖI) =================
def get_active_context(query: str, user_id: str, notebook_id: str, k_needed: int = 15, return_refs: bool = False):
    valid_docs = []
    COSINE_THRESHOLD = 0.55 
    
    try:
        # Bọc thép chống lỗi nếu notebook_id bị trống
        try:
            n_id = int(notebook_id)
        except ValueError:
            n_id = 0
            
        # 1. Biến câu hỏi thành Vector
        query_vector = embeddings.embed_query(query)
        
        # 2. 🚀 GỌI TRỰC TIẾP SUPABASE (Bỏ qua Langchain để không bị nuốt lỗi ngầm)
        res = supabase.rpc("match_documents", {
            "query_embedding": query_vector,
            "match_count": 50,
            "filter": {"user_id": user_id, "notebook_id": n_id}
        }).execute()
        
        if not res.data:
            return ("", []) if return_refs else ""
            
        # 3. Trích xuất tài liệu
        query_lower = query.lower()
        is_meta_query = any(kw in query_lower for kw in ["tóm tắt", "tổng quan", "nội dung", "ý chính", "file này", "tài liệu", "là gì"])
        
        for row in res.data:
            score = row.get("similarity", 1.0)
            content = row.get("content", "")
            metadata = row.get("metadata", {})
            
            if return_refs:
                if is_meta_query or score <= COSINE_THRESHOLD:
                    valid_docs.append({"content": content, "metadata": metadata})
            else:
                valid_docs.append({"content": content, "metadata": metadata})
                
    except Exception as e:
        # 🚨 Nếu có lỗi ngầm, sẽ in ra RÕ RÀNG chi tiết đỏ chót trên Terminal
        print(f"🔥 LỖI TÌM KIẾM VECTOR: {repr(e)}")
        if hasattr(e, 'details'): print(f"Chi tiết: {e.details}")
        return ("", []) if return_refs else ""
        
    if not valid_docs:
        return ("", []) if return_refs else ""
    
    formatted_contexts = []
    source_map = []
    
    for i, doc in enumerate(valid_docs[:k_needed]):
        metadata = doc["metadata"]
        fname = metadata.get("filename", "Không rõ tài liệu")
        page = metadata.get("page", "?")
        source_id = i + 1 
        chunk_id = f"chk_{notebook_id}_{source_id}_{i}"
        
        formatted_contexts.append(f"--- NGUỒN [{source_id}] ---\nTài liệu: {fname} (Trang {page})\nNội dung: {doc['content']}")
        source_map.append({"id": source_id, "file": fname, "page": page, "chunk_id": chunk_id})
        
    context_str = "\n\n".join(formatted_contexts)
    
    if return_refs:
        return context_str, source_map 
    return context_str