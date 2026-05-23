from fastapi import FastAPI, UploadFile, File, HTTPException, Request, Form
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import PyPDF2
import fitz  # Thư viện PyMuPDF thay thế PyPDF2
import io
import os
import bcrypt
import jwt
import shutil
import json
import hashlib
import os
from dotenv import load_dotenv
import random
from datetime import datetime, timedelta
import edge_tts
from groq import Groq 
from supabase import create_client, Client
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS

# Khởi động lệnh: uvicorn main:app --host 0.0.0.0 --port 8000
load_dotenv()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ================= CẤU TRÚC DỮ LIỆU INPUT =================
class ChatRequest(BaseModel):
    user_id: str
    notebook_id: str
    message: str

class ScoreRequest(BaseModel):
    user_id: str
    topic: str
    score: int
    total: int

class WeaknessRequest(BaseModel):
    user_id: str
    notebook_id: str
    wrong_questions: list

class AuthRequest(BaseModel):
    username: str
    password: str

class NoteRequest(BaseModel):
    user_id: str
    title: str
    content: str

class NotebookRequest(BaseModel):
    user_id: str
    title: str

# ================= KHỞI TẠO EMBEDDINGS VÀ KẾT NỐI KHÔNG GIAN LƯU TRỮ =================
print("Đang khởi tạo mô hình nhúng văn bản...")
embeddings = HuggingFaceEmbeddings(model_name="keepitreal/vietnamese-sbert") 
text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=100)

# Chuyển đổi hằng số cũ thành thư mục gốc chứa các bộ cơ sở dữ liệu vector riêng biệt
VECTOR_DB_ROOT = "vector_db"

print("Đang đồng bộ hóa cơ sở dữ liệu Supabase Cloud...")
# Điền thông tin thông qua biến môi trường
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
print("✅ Đồng bộ hóa Supabase Cloud thành công!")

# ================= CẤU HÌNH MÔ HÌNH NGÔN NGỮ LỚN GROQ AI =================
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "") 
groq_client = Groq(api_key=GROQ_API_KEY)
GROQ_MODEL = "llama-3.3-70b-versatile" 

def call_groq(prompt: str, is_chat_mode: bool = False, temp: float = 0.2):
    try:
        sys_msg = (
            "Bạn là một Giáo sư đại học uyên bác và cực kỳ nhiệt tình. BẮT BUỘC TRẢ LỜI DÀI, CHI TIẾT VÀ SÂU SẮC NHẤT CÓ THỂ. "
            "Hãy phân tích đa chiều, giải thích cặn kẽ nguyên lý (Tại sao lại như vậy?), mở rộng vấn đề và lấy ví dụ minh họa rõ ràng. "
            "Tuyệt đối KHÔNG trả lời ngắn gọn, cụt lủn hay lười biếng. Trình bày bài bản bằng heading và gạch đầu dòng."
            if is_chat_mode else
            "Bạn là AI tạo dữ liệu. Tuân thủ tuyệt đối định dạng JSON được yêu cầu, KHÔNG giải thích dông dài."
        )
        
        chat_completion = groq_client.chat.completions.create(
            messages=[
                {"role": "system", "content": sys_msg},
                {"role": "user", "content": prompt}
            ],
            model=GROQ_MODEL,
            temperature=temp, 
            max_tokens=2048, # 🔥 ÉP GIỚI HẠN CHỮ LÊN MỨC KHỦNG (Khoảng 2000 từ) để AI tha hồ viết dài
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
            if "options" in required_keys and not isinstance(item.get("options"), list): continue
            if "tasks" in required_keys and not isinstance(item.get("tasks"), list): continue
            valid_items.append(item)
            
    if not valid_items: raise ValueError("Dữ liệu rỗng hoặc sai cấu trúc")
    return valid_items

# 🛡️ ĐƯỜNG DẪN ĐƯỢC CHUYỂN ĐỔI ĐỘNG CÓ KÈM TRÍCH DẪN NGUỒN
def get_active_context(query: str, user_id: str, notebook_id: str, k_needed: int = 15):
    # ĐƯỜNG DẪN MỚI: Trỏ thẳng vào phân vùng con của Notebook
    user_vector_path = os.path.join(VECTOR_DB_ROOT, user_id, notebook_id)
    if not os.path.exists(user_vector_path): 
        return ""
    
    vector_db = FAISS.load_local(user_vector_path, embeddings, allow_dangerous_deserialization=True)
    docs = vector_db.similarity_search(query, k=50) 
    
    try:
        # NÂNG CẤP TRUY VẤN: Lọc thêm điều kiện .eq("notebook_id", int(notebook_id))
        res = supabase.table("uploaded_files").select("filename").eq("user_id", user_id).eq("notebook_id", int(notebook_id)).execute()
        active_files = [r['filename'] for r in res.data]
    except: 
        active_files = []
        
    if not active_files: 
        return ""
    
    valid_docs = [d for d in docs if d.metadata.get("filename") in active_files]
    
    formatted_contexts = []
    for doc in valid_docs[:k_needed]:
        fname = doc.metadata.get("filename", "Không rõ tài liệu")
        page = doc.metadata.get("page", "?")
        formatted_contexts.append(f"[THÔNG TIN TRÍCH TỪ: {fname} - Trang {page}]\n{doc.page_content}")
        
    return "\n\n---\n\n".join(formatted_contexts)


# ================= HỆ THỐNG ĐIỂM CUỐI API (API ENDPOINTS) =================

@app.get("/")
async def root():
    return {"status": "online", "message": "Hệ thống Không gian học tập phân tách an toàn đang hoạt động! 🚀"}

# --- API: GIỌNG NÓI ĐÁM MÂY EDGE TTS ---
@app.get("/api/tts")
async def text_to_speech(text: str):
    try:
        communicate = edge_tts.Communicate(text, "vi-VN-HoaiMyNeural", rate="+5%") 
        audio_data = b""
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio_data += chunk["data"]
        return StreamingResponse(io.BytesIO(audio_data), media_type="audio/mpeg")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- API: TẢI FILE PDF (ĐÃ NÂNG CẤP LÕI PYMUPDF ĐỌC CHUẨN TIẾNG VIỆT) ---
@app.post("/api/upload")
async def upload_pdf(file: UploadFile = File(...), user_id: str = Form(...), notebook_id: str = Form(...)): # 👈 THÊM THAM SỐ Ở ĐÂY
    try:
        content = await file.read()
        pdf_document = fitz.open(stream=content, filetype="pdf")
        
        chunks = []
        metadatas = []
        
        for page_num in range(len(pdf_document)):
            page = pdf_document.load_page(page_num)
            extracted = page.get_text("text") 
            if extracted.strip():
                page_chunks = text_splitter.split_text(extracted)
                chunks.extend(page_chunks)
                metadatas.extend([{"filename": file.filename, "page": page_num + 1} for _ in page_chunks])
        
        # 📂 ĐƯỜNG DẪN MỚI: Lưu trữ biệt lập theo từng Notebook
        user_vector_path = os.path.join(VECTOR_DB_ROOT, user_id, notebook_id)
        
        if os.path.exists(user_vector_path):
            vector_db = FAISS.load_local(user_vector_path, embeddings, allow_dangerous_deserialization=True)
            vector_db.add_texts(chunks, metadatas=metadatas) 
        else:
            vector_db = FAISS.from_texts(chunks, embeddings, metadatas=metadatas) 
        vector_db.save_local(user_vector_path)

        # 💾 SUPABASE UPDATE: Đẩy thêm cột notebook_id lên Cloud
        supabase.table("uploaded_files").insert({
            "user_id": user_id, 
            "filename": file.filename,
            "notebook_id": int(notebook_id) # 👈 Ghi nhận file thuộc Notebook nào
        }).execute()
        
        return {"status": "success", "message": f"Đã học xong {file.filename} vào cấu trúc Notebook!"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/files/{user_id}")
async def get_uploaded_files(user_id: str):
    response = supabase.table("uploaded_files").select("*").eq("user_id", user_id).order("upload_date", desc=True).execute()
    return [{"id": r['id'], "filename": r['filename'], "date": r['upload_date']} for r in response.data]

# --- API: XÓA FILE TẬN GỐC (XÓA CẢ SUPABASE VÀ VECTOR FAISS) ---
@app.delete("/api/files/{file_id}")
async def delete_file_history(file_id: int):
    try:
        res = supabase.table("uploaded_files").select("user_id", "filename", "notebook_id").eq("id", file_id).execute()
        if not res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy tài liệu này.")
            
        user_id = res.data[0]['user_id']
        filename = res.data[0]['filename']
        notebook_id = res.data[0]['notebook_id'] 
        
        user_vector_path = os.path.join(VECTOR_DB_ROOT, user_id, str(notebook_id))
        if os.path.exists(user_vector_path):
            vector_db = FAISS.load_local(user_vector_path, embeddings, allow_dangerous_deserialization=True)
            
            ids_to_delete = [
                doc_id for doc_id, doc in vector_db.docstore._dict.items()
                if doc.metadata.get("filename") == filename
            ]
            
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

# --- API: TẨY NÃO CÁ NHÂN (XÓA BỘ NHỚ VECTOR RIÊNG BIỆT) ---
@app.delete("/api/files/reset/{user_id}")
async def reset_ai_brain(user_id: str):
    user_vector_path = os.path.join(VECTOR_DB_ROOT, user_id)
    if os.path.exists(user_vector_path): 
        shutil.rmtree(user_vector_path)
    supabase.table("uploaded_files").delete().eq("user_id", user_id).execute()
    return {"status": "success", "message": "Đã làm sạch không gian bộ nhớ cá nhân của bạn!"}

# --- API: GIA SƯ TRÒ CHUYỆN CHUYÊN SÂU ---
# --- API: GIA SƯ TRÒ CHUYỆN CHUYÊN SÂU (ĐÃ NÂNG CẤP STREAMING TỐC ĐỘ CAO) ---
# --- API: GIA SƯ TRÒ CHUYỆN CHUYÊN SÂU (STREAMING + TRẢ LỜI CỰC DÀI) ---
# --- API: GIA SƯ TRÒ CHUYỆN CHUYÊN SÂU (ĐÃ THÊM CỔNG KIỂM DUYỆT CHỦ ĐỀ) ---
# --- API: GIA SƯ TRÒ CHUYỆN CHUYÊN SÂU (CÓ LƯU LỊCH SỬ) ---
@app.post("/api/chat")
async def chat_with_ai(request: ChatRequest):
    try:
        # 1. NGAY LẬP TỨC LƯU CÂU HỎI CỦA USER VÀO DATABASE
        supabase.table("chat_history").insert({
            "user_id": request.user_id, 
            "notebook_id": int(request.notebook_id), 
            "sender": "user", 
            "message": request.message
        }).execute()

        context = get_active_context(request.message, request.user_id, request.notebook_id, k_needed=12)
        user_vector_path = os.path.join(VECTOR_DB_ROOT, request.user_id, request.notebook_id)
        
        if not context and not os.path.exists(user_vector_path):
            async def quick_reply():
                yield "Vui lòng tải tài liệu PDF lên trước nhé! 📚"
            return StreamingResponse(quick_reply(), media_type="text/plain")
            
        prompt = f"""
        TÀI LIỆU HỌC TẬP THUỘC VỀ USER {request.user_id}: 
        {context}
        
        CÂU HỎI CỦA HỌC SINH: {request.message}
        
        ⛔ LƯU Ý SỐNG CÒN (CỔNG KIỂM DUYỆT):
        - Đầu tiên, hãy đánh giá xem CÂU HỎI có nằm trong nội dung của TÀI LIỆU hay không.
        - Nếu KHÔNG LIÊN QUAN, BẮT BUỘC TỪ CHỐI: "Xin lỗi, thông tin bạn hỏi không có trong tài liệu hiện tại." và KHÔNG viết thêm gì cả.
        
        ✅ YÊU CẦU DÀNH CHO GIA SƯ:
        1. BẮT BUỘC DỰA 100% VÀO TÀI LIỆU: Tuyệt đối không được bịa đặt (hallucinate) hay dùng kiến thức ngoài đời thực. Nếu thông tin không có trong tài liệu, BẮT BUỘC trả lời "Tài liệu không đề cập".
        2. CHI TIẾT NHƯNG CHUẨN XÁC: Giải thích cặn kẽ dựa trên ĐÚNG nội dung tài liệu cung cấp.
        3. Cấu trúc trình bày bài bản: Mở bài - Thân bài (in đậm, gạch đầu dòng) - Kết luận.
        4. BẮT BUỘC TRÍCH DẪN NGAY LẬP TỨC (INLINE CITATION): Viết xong ý nào phải cắm ngay nút trích dẫn vào cuối câu đó.
           -> Cú pháp (bắt đầu bằng http://ref/): [📚 Trích Trang X](http://ref/Tên_File.pdf|X)
        """

        async def generate_chat():
            full_ai_response = "" # Biến để hứng toàn bộ câu trả lời của AI
            try:
                chat_completion = groq_client.chat.completions.create(
                    messages=[
                        {"role": "system", "content": "Bạn là Giáo sư AI..."},
                        {"role": "user", "content": prompt}
                    ],
                    model=GROQ_MODEL,
                    temperature=0.4, 
                    max_tokens=3000, 
                    stream=True
                )
                
                for chunk in chat_completion:
                    if chunk.choices[0].delta.content:
                        text_chunk = chunk.choices[0].delta.content
                        full_ai_response += text_chunk # Cộng dồn chữ vào biến
                        yield text_chunk
                
                # 2. KHI AI TRẢ LỜI XONG (HẾT VÒNG LẶP), LƯU CÂU TRẢ LỜI ĐÓ VÀO DATABASE
                if full_ai_response:
                    supabase.table("chat_history").insert({
                        "user_id": request.user_id, 
                        "notebook_id": int(request.notebook_id), 
                        "sender": "ai", 
                        "message": full_ai_response
                    }).execute()
                    
            except Exception as e:
                yield f"\n[Lỗi kết nối AI: {str(e)}]"

        return StreamingResponse(generate_chat(), media_type="text/plain")
        
    except Exception as e:
        async def error_reply():
            yield f"Hệ thống báo lỗi: {str(e)}"
        return StreamingResponse(error_reply(), media_type="text/plain")
    

# --- API: TẠO QUIZ NGẪU NHIÊN PHÂN TẦNG (ĐÃ KHÔI PHỤC KỶ LUẬT THÉP) ---
@app.post("/api/quiz")
async def generate_quiz(request: Request): 
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        num_questions = data.get("num_questions", 5) 
        difficulty = data.get("difficulty", "Trung bình")
        
        search_query = "Tất cả các định nghĩa, khái niệm, đặc điểm, công thức, nguyên lý, ví dụ và ứng dụng trong toàn bộ tài liệu"
        context = get_active_context(search_query, user_id, k_needed=15)
        
        if not context:
            return {"data": [{"question": "Bạn chưa tải file PDF hoặc file đã bị xóa sạch! Hãy tải tài liệu mới lên nhé.", "options": ["Đã hiểu"], "answer": "Đã hiểu"}]}
            
        difficulty_instruction = ""
        if difficulty == "Dễ":
            difficulty_instruction = "MỨC ĐỘ DỄ: Chỉ hỏi trực tiếp vào định nghĩa cơ bản. Đáp án sai phải CỰC KỲ VÔ LÝ để dễ loại trừ."
        elif difficulty == "Trung bình":
            difficulty_instruction = "MỨC ĐỘ TRUNG BÌNH: CẤM hỏi kiểu định nghĩa '... là gì?'. Phải đưa ra đặc điểm, nguyên lý hoạt động, hoặc một VÍ DỤ/TÌNH HUỐNG NGẮN."
        elif difficulty == "Khó":
            difficulty_instruction = """
            - MỨC ĐỘ CỰC KHÓ (VẬN DỤNG CAO):
            1. DẠNG CÂU HỎI BẮT BUỘC: Bắt buộc 100% phải dùng cấu trúc "Phát biểu nào sau đây là ĐÚNG (hoặc SAI) khi nói về [Khái niệm]?" hoặc "Khẳng định nào sau đây KHÔNG CHÍNH XÁC?".
            2. CẤU TRÚC ĐÁP ÁN: Các đáp án phải là các mệnh đề/câu văn dài phân tích bản chất. 
            3. ĐÁP ÁN BẪY: 3 mệnh đề sai phải cực kỳ tinh vi, dùng đúng thuật ngữ trong tài liệu nhưng cố tình viết sai lệch đi một nửa ý nghĩa ở cuối câu để lừa người đọc.
            """
        elif difficulty == "Khó":
            difficulty_instruction = """
            - MỨC ĐỘ CỰC KHÓ (VẬN DỤNG CAO):
            1. DẠNG CÂU HỎI BẮT BUỘC: Bắt buộc 100% phải dùng cấu trúc "Phát biểu nào sau đây là ĐÚNG (hoặc SAI) khi nói về [Khái niệm]?" hoặc "Khẳng định nào sau đây KHÔNG CHÍNH XÁC?".
            2. CẤU TRÚC ĐÁP ÁN: Các đáp án phải là các mệnh đề/câu văn dài phân tích bản chất. 
            3. ĐÁP ÁN BẪY: 3 mệnh đề sai phải cực kỳ tinh vi, dùng đúng thuật ngữ trong tài liệu nhưng cố tình viết sai lệch đi một nửa ý nghĩa ở cuối câu để lừa người đọc.
            """
        # BỔ SUNG ĐOẠN NÀY DÀNH RIÊNG CHO PHÒNG THI ẢO
        elif difficulty == "Phòng thi ảo":
            difficulty_instruction = """
            - MỨC ĐỘ TỔNG HỢP (PHÒNG THI CHÍNH THỨC):
            BẮT BUỘC TRỘN LẪN độ khó cho toàn bộ đề thi theo tỷ lệ sau:
            1. Nhóm DỄ (30% số câu): Hỏi trực tiếp định nghĩa cơ bản, đáp án sai dễ loại trừ.
            2. Nhóm TRUNG BÌNH (40% số câu): CẤM hỏi định nghĩa. Hãy hỏi về ví dụ, đặc điểm, hoặc nguyên lý hoạt động.
            3. Nhóm KHÓ (30% số câu): BẮT BUỘC dùng cấu trúc "Phát biểu nào sau đây là ĐÚNG (hoặc SAI)?". Các đáp án bẫy phải cực kỳ tinh vi, dùng mệnh đề dài để phân loại học sinh khá giỏi.
            (Đảm bảo các mức độ này xuất hiện xen kẽ nhau trong mảng JSON).
            """

        # Tạo một con số ngẫu nhiên để ép AI không được dùng lại vùng nhớ đệm cũ
        random_seed = random.randint(1000, 99999)

        prompt = f"""
        Bạn là giáo sư đại học. Dựa vào TÀI LIỆU sau, tạo {num_questions} câu hỏi trắc nghiệm.
        TÀI LIỆU: {context}
        
        CHÚ Ý CỰC KỲ QUAN TRỌNG: 
        {difficulty_instruction}
        
        - MỆNH LỆNH ĐỔI MỚI (Mã phiên bản: {random_seed}): TUYỆT ĐỐI KHÔNG chọn lại những phần kiến thức hiển nhiên ở đầu trang. Bắt buộc bốc NGẪU NHIÊN các khái niệm/tình huống nằm rải rác sâu bên trong hoặc ở cuối tài liệu. Mỗi lần tạo là một bộ câu hỏi hoàn toàn mới!
        
        YÊU CẦU BẮT BUỘC: Trả về CHỈ 1 MẢNG JSON thuần túy, tuyệt đối không có markdown hay bất kỳ lời giải thích nào.
        Cấu trúc mẫu chuẩn:
        [{{\"question\": \"Thủ đô của Việt Nam là gì?\", \"options\": [\"Hà Nội\", \"Huế\", \"Đà Nẵng\", \"TP.HCM\"], \"answer\": \"Hà Nội\"}}]
        
        LƯU Ý SỐNG CÒN: Trường "answer" phải CHÉP LẠI Y HỆT NỘI DUNG CHỮ của đáp án đúng từ mảng "options". TUYỆT ĐỐI KHÔNG ĐƯỢC trả về số thứ tự.
        """
        
        # GỌI AI VỚI NHIỆT ĐỘ 0.7 ĐỂ KÍCH THÍCH SỰ SÁNG TẠO VÀ KHÁC BIỆT
        raw_text = call_groq(prompt, is_chat_mode=False, temp=0.7).replace("```json", "").replace("```", "").strip()
        quiz_data = extract_json_array(json.loads(raw_text), ["question", "options", "answer"]) 
        return {"data": quiz_data}
    except Exception as e:
        print(f"Lỗi tạo đề: {str(e)}")
        return {"data": [{"question": "Hệ thống bị gián đoạn hoặc AI từ chối định dạng. Xin hãy thử lại!", "options": ["OK"], "answer": "OK"}]}
    
    
# --- API: BẮT MẠCH ĐIỂM YẾU VÀ TẠO ĐỀ KHẮC PHỤC ---
@app.post("/api/analyze_weakness")
async def analyze_weakness(request: WeaknessRequest):
    try:
        if not request.wrong_questions:
            return {"status": "success", "data": {"report": "🎉 Tuyệt vời! Bạn đã làm đúng 100% không sai câu nào.", "quiz": []}}
            
        search_query = " ".join(request.wrong_questions)
        context = get_active_context(search_query, request.user_id, request.notebook_id, k_needed=10)
        
        prompt = f"""
        Học sinh vừa làm bài thi và bị TÍNH TOÁN SAI ở các câu hỏi sau:
        {request.wrong_questions}
        
        TÀI LIỆU HỌC TẬP CỦA HỌC SINH:
        {context}
        
        HÃY ĐÓNG VAI GIA SƯ VÀ THỰC HIỆN 2 NHIỆM VỤ (Trả về định dạng JSON):
        1. "report": Viết một đoạn Báo Cáo Học Tập (khoảng 4-5 câu). Nhẹ nhàng an ủi, CHỈ RA RÕ RÀNG học sinh đang hiểu sai hoặc hổng kiến thức ở phần nào. Sau đó, TÓM TẮT NGẮN GỌN LẠI KIẾN THỨC ĐÚNG từ tài liệu để học sinh ôn ngay lập tức. Trình bày có dùng icon cho sinh động.
        2. "quiz": Tạo ra 3 câu hỏi trắc nghiệm MỚI TINH, mức độ Trung Bình - Khó, xoáy sâu trực tiếp vào đúng những phần kiến thức học sinh vừa sai để kiểm tra lại.
        
        YÊU CẦU BẮT BUỘC VỀ JSON:
        {{
            "report": "Phân tích và tóm tắt kiến thức của AI...",
            "quiz": [
                {{"question": "Thủ đô của Việt Nam?", "options": ["Hà Nội", "Huế", "Đà Nẵng", "TP.HCM"], "answer": "Hà Nội"}}
            ]
        }}
        LƯU Ý SỐNG CÒN: Ở mảng "quiz", trường "answer" phải CHÉP LẠI Y HỆT NỘI DUNG CHỮ của đáp án đúng từ mảng "options". TUYỆT ĐỐI KHÔNG ĐƯỢC trả về số thứ tự (1, 2, 3, 4).
        """
        raw_text = call_groq(prompt).replace("```json", "").replace("```", "").strip()
        parsed_data = json.loads(raw_text)
        valid_quiz = extract_json_array(parsed_data.get("quiz", []), ["question", "options", "answer"])
        
        return {
            "status": "success", 
            "data": {
                "report": parsed_data.get("report", "Không thể tạo báo cáo lúc này."),
                "quiz": valid_quiz
            }
        }
    except Exception as e:
        return {"status": "error", "message": "Lỗi hệ thống phân tích bối cảnh sai lỗ."}

# --- API: TẠO FLASHCARD CÁ NHÂN ---
@app.post("/api/flashcards")
async def generate_flashcards(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        num_cards = data.get("num_cards", 5)
        
        search_query = "Các thuật ngữ, định nghĩa, khái niệm cốt lõi, từ khóa quan trọng trải dài toàn bài"
        context = get_active_context(search_query, user_id, k_needed=15)
        
        if not context:
            return {"data": [{"term": "Chưa tải PDF", "definition": "Vui lòng tải tài liệu mới lên trang chủ trước nhé!"}]}
            
        prompt = f"""
        Dựa vào tài liệu sau, tạo {num_cards} thẻ ghi nhớ (Flashcard).
        TÀI LIỆU: {context}
        
        CHÚ Ý: Trích xuất các thuật ngữ trải đều từ khắp các phần của bài học.
        YÊU CẦU: Trả về CHỈ 1 MẢNG JSON.
        [{{\"term\": \"A\", \"definition\": \"B\"}}]
        """
        raw_text = call_groq(prompt).replace("```json", "").replace("```", "").strip()
        flashcards = extract_json_array(json.loads(raw_text), ["term", "definition"]) 
        return {"data": flashcards}
    except Exception:
        return {"data": [{"term": "Lỗi", "definition": "Không thể tạo lúc này, vui lòng thử lại!"}]}

# --- API: TẠO LỘ TRÌNH HỌC TẬP BAO QUÁT ---
@app.post("/api/roadmap")
async def generate_roadmap(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        
        search_query = "Tóm tắt nội dung chính, mục lục, các chương, các phần, chủ đề cốt lõi toàn bài"
        context = get_active_context(search_query, user_id, k_needed=15)
        
        if not context:
            return {"data": [{"day": "Lỗi", "title": "Chưa có PDF", "tasks": ["Tải tài liệu lên trang chủ trước nha!"]}]}
            
        prompt = f"Dựa vào TÀI LIỆU sau, tạo Lộ trình học 5 giai đoạn bao quát toàn bộ tài liệu.\nTÀI LIỆU: {context}\nYÊU CẦU: Trả về CHỈ 1 MẢNG JSON.\n[{{\"day\": \"Giai đoạn 1\", \"title\": \"Nắm bắt\", \"tasks\": [\"A\", \"B\"]}}]"
        raw_text = call_groq(prompt).replace("```json", "").replace("```", "").strip()
        roadmap_data = extract_json_array(json.loads(raw_text), ["day", "title", "tasks"]) 
        return {"data": roadmap_data}
    except Exception:
        return {"data": [{"day": "Lỗi hệ thống", "title": "AI từ chối định dạng", "tasks": ["Xin bấm tạo lại lộ trình!"]}]}

# --- CÁC API HỆ THỐNG SUPABASE (GIỮ NGUYÊN TRẠNG) ---
@app.post("/api/score")
async def save_score(request: ScoreRequest):
    phan_tram = round((request.score / request.total) * 100, 2) if request.total > 0 else 0
    supabase.table("history").insert({
        "user_id": request.user_id, "topic": request.topic, "score": request.score, 
        "total_questions": request.total, "percentage": phan_tram
    }).execute()
    return {"status": "success"}

@app.get("/api/history/{user_id}")
async def get_history(user_id: str):
    response = supabase.table("history").select("*").eq("user_id", user_id).order("created_at", desc=True).limit(20).execute()
    return [{"topic": r['topic'], "score": r['score'], "total": r['total_questions'], "percentage": r['percentage'], "date": r['created_at']} for r in response.data]

@app.get("/api/dashboard/{user_id}")
async def get_dashboard_data(user_id: str):
    today = datetime.now().date()
    today_str = today.strftime("%Y-%m-%d")
    
    res = supabase.table("user_stats").select("*").eq("user_id", user_id).execute()
    streak = 1
    if res.data:
        old_data = res.data[0]
        last_login = datetime.strptime(old_data['last_login'], "%Y-%m-%d").date()
        if last_login == today - timedelta(days=1): streak = old_data['streak'] + 1
        elif last_login == today: streak = old_data['streak']
    
    supabase.table("user_stats").upsert({"user_id": user_id, "streak": streak, "last_login": today_str}).execute()

    hist_res = supabase.table("history").select("*").eq("user_id", user_id).order("created_at", desc=True).limit(6).execute()
    notifications = []
    if not hist_res.data:
        notifications.append({"type": "info", "message": "👋 Chào mừng bạn mới! Hãy tải tài liệu PDF lên và bắt đầu trò chuyện với AI nhé.", "time": "Vừa xong"})
    else:
        for r in hist_res.data:
            pct = r['percentage']
            if pct >= 80: t, msg = "success", f"Tuyệt vời! Đạt {pct}% bài {r['topic']}."
            elif pct >= 50: t, msg = "warning", f"Khá tốt! Đạt {pct}% bài {r['topic']}."
            else: t, msg = "danger", f"Cảnh báo: Điểm {r['topic']} chỉ đạt {pct}%."
            notifications.append({"type": t, "message": msg, "time": r['created_at'].split("T")[0]})

    return {"status": "success", "streak": streak, "notifications": notifications}

@app.get("/api/recommend/{user_id}")
async def get_recommendation(user_id: str):
    res = supabase.table("history").select("percentage").eq("user_id", user_id).order("created_at", desc=True).limit(5).execute()
    if not res.data: return {"recommendation": "Chào mừng bạn! Hãy làm bài Quiz đầu tiên nhé."}
    avg_score = sum([r['percentage'] for r in res.data]) / len(res.data)
    try: return {"recommendation": call_groq(f"Nhận xét 2 câu cho học sinh đạt {avg_score}%").strip()}
    except: return {"recommendation": "Chưa thể đưa ra nhận xét lúc này."}

@app.post("/api/notes")
async def add_note(request: NoteRequest):
    supabase.table("notes").insert({"user_id": request.user_id, "title": request.title, "content": request.content}).execute()
    return {"status": "success"}

@app.get("/api/notes/{user_id}")
async def get_notes(user_id: str):
    response = supabase.table("notes").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
    return [{"id": r['id'], "title": r['title'], "content": r['content'], "date": r['created_at']} for r in response.data]

@app.delete("/api/notes/{note_id}")
async def delete_note(note_id: int):
    supabase.table("notes").delete().eq("id", note_id).execute()
    return {"status": "success"}

# ================= BẢO MẬT: BCRYPT & JWT =================
SECRET_KEY = "CHIA_KHOA_BI_MAT_CUA_SANG_AI_STUDY" 
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7 

def hash_password(password: str) -> str:
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.now() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": int(expire.timestamp())})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

@app.post("/api/register")
async def register(request: AuthRequest):
    try:
        res = supabase.table("users").select("*").eq("username", request.username).execute()
        if res.data: raise HTTPException(status_code=400, detail="Tên đăng nhập đã tồn tại!")
        
        hashed_pw = hash_password(request.password)
        supabase.table("users").insert({"username": request.username, "password": hashed_pw}).execute()
        return {"status": "success", "message": "Đăng ký thành công!"}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/login")
async def login(request: AuthRequest):
    res = supabase.table("users").select("*").eq("username", request.username).execute()
    
    if not res.data: 
        raise HTTPException(status_code=400, detail="Sai tên đăng nhập hoặc mật khẩu!")
        
    user = res.data[0]
    
    if not verify_password(request.password, user['password']):
        raise HTTPException(status_code=400, detail="Sai tên đăng nhập hoặc mật khẩu!")
    
    access_token = create_access_token(data={"sub": user['username']})
    
    return {
        "status": "success", 
        "username": user['username'],
        "token": access_token 
    }

# --- API: LỤC LỌI LÝ THUYẾT GỐC TỪ SỐ TRANG ---

@app.get("/api/reference")
async def get_reference_content(user_id: str, filename: str, page: int, notebook_id: str = ""):
    try:
        # Tương thích với cả cấu trúc có hoặc không có notebook_id
        if notebook_id:
            user_vector_path = os.path.join(VECTOR_DB_ROOT, user_id, notebook_id)
        else:
            user_vector_path = os.path.join(VECTOR_DB_ROOT, user_id)
            
        if not os.path.exists(user_vector_path):
            return {"status": "error", "data": "Không tìm thấy dữ liệu học tập."}

        vector_db = FAISS.load_local(user_vector_path, embeddings, allow_dangerous_deserialization=True)
        
        # 🧠 HÀM CHUẨN HÓA THẦN THÁNH: 
        # Xóa sạch khoảng trắng, dấu gạch dưới và %20 để so sánh tuyệt đối
        def normalize_filename(name):
            return name.replace("_", "").replace(" ", "").replace("%20", "").lower()
            
        target_filename = normalize_filename(filename)
        
        original_chunks = []
        for doc_id, doc in vector_db.docstore._dict.items():
            db_filename = normalize_filename(doc.metadata.get("filename", ""))
            
            # So sánh tên file đã chuẩn hóa thay vì tên gốc
            if db_filename == target_filename and doc.metadata.get("page") == page:
                original_chunks.append(doc.page_content)

        if not original_chunks:
            return {"status": "success", "data": "Không trích xuất được lý thuyết chi tiết cho trang này."}

        raw_theory = "\n\n...\n\n".join(original_chunks)
        
        # 👇 ĐƯA VĂN BẢN THÔ CHO AI SẮP XẾP LẠI FORMAT ĐẸP (MARKDOWN)
        format_prompt = f"""
        Đây là văn bản bóc tách thô từ file PDF. Nó đang bị mất định dạng bảng biểu và xuống dòng.
        HÃY LÀM 2 VIỆC:
        1. Định dạng lại nó bằng Markdown (Nếu thấy giống dữ liệu bảng, hãy kẻ bảng Markdown. Thêm in đậm, gạch đầu dòng cho dễ đọc).
        2. TUYỆT ĐỐI GIỮ NGUYÊN 100% THÔNG TIN. KHÔNG THÊM BỚT BẤT KỲ CHỮ NÀO CỦA TÀI LIỆU.
        
        VĂN BẢN THÔ:
        {raw_theory}
        """
        # Dùng temp thấp (0.1) để AI biến thành cỗ máy format, không sáng tạo thêm chữ
        formatted_theory = call_groq(format_prompt, is_chat_mode=False, temp=0.1)
        
        return {"status": "success", "data": formatted_theory}
    except Exception as e:
        return {"status": "error", "data": f"Lỗi trích xuất: {str(e)}"}
    
@app.post("/api/notebooks")
async def create_notebook(request: NotebookRequest):
    res = supabase.table("notebooks").insert({"user_id": request.user_id, "title": request.title}).execute()
    return {"status": "success", "data": res.data[0]}

@app.get("/api/notebooks/{user_id}")
async def get_notebooks(user_id: str):
    res = supabase.table("notebooks").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
    return res.data

@app.delete("/api/notebooks/{notebook_id}")
async def delete_notebook(notebook_id: int):
    # Xóa folder vector của notebook này
    res = supabase.table("notebooks").select("user_id").eq("id", notebook_id).execute()
    if res.data:
        path = os.path.join(VECTOR_DB_ROOT, res.data[0]['user_id'], str(notebook_id))
        if os.path.exists(path): shutil.rmtree(path)
    supabase.table("notebooks").delete().eq("id", notebook_id).execute()
    return {"status": "success"}

# --- API: LẤY LỊCH SỬ CHAT THEO NOTEBOOK ---
@app.get("/api/chat_history/{user_id}/{notebook_id}")
async def get_chat_history(user_id: str, notebook_id: int):
    try:
        res = supabase.table("chat_history").select("*").eq("user_id", user_id).eq("notebook_id", notebook_id).order("created_at", desc=False).execute()
        return {"status": "success", "data": res.data}
    except Exception as e:
        return {"status": "error", "message": str(e)}