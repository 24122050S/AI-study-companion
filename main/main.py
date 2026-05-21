from fastapi import FastAPI, UploadFile, File, HTTPException, Request, Form
from fastapi.responses import StreamingResponse # Dùng cho Edge TTS
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import PyPDF2
import io
import os
import shutil
import json
import random
import hashlib
from datetime import datetime, timedelta
import edge_tts # Thư viện giọng nói siêu chuẩn của Microsoft
from groq import Groq 
from supabase import create_client, Client
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS

# uvicorn main:app --host 0.0.0.0 --port 8000

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ================= CẤU TRÚC DỮ LIỆU =================
class ChatRequest(BaseModel):
    user_id: str
    message: str

class ScoreRequest(BaseModel):
    user_id: str
    topic: str
    score: int
    total: int

class WeaknessRequest(BaseModel):
    user_id: str
    wrong_questions: list  # Danh sách nội dung các câu học sinh chọn sai

class AuthRequest(BaseModel):
    username: str
    password: str

class NoteRequest(BaseModel):
    user_id: str
    title: str
    content: str

# ================= KHỞI TẠO HỆ THỐNG VÀ EMBEDDING =================
print("Đang khởi tạo hệ thống RAG...")
embeddings = HuggingFaceEmbeddings(model_name="keepitreal/vietnamese-sbert") 
text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=100)
VECTOR_DB_PATH = "my_vector_db"

print("Kết nối Supabase...")
# LƯU Ý: ĐIỀN THÔNG TIN SUPABASE CỦA BẠN VÀO ĐÂY
SUPABASE_URL = ""
SUPABASE_KEY = ""
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
print("✅ Đã kết nối Supabase Cloud thành công!")

# ================= CẤU HÌNH GROQ AI =================
GROQ_API_KEY = "" 
groq_client = Groq(api_key=GROQ_API_KEY)
GROQ_MODEL = "llama-3.3-70b-versatile" 

def call_groq(prompt: str, is_chat_mode: bool = False, temp: float = 0.2):
    try:
        sys_msg = (
            "Bạn là Gia sư AI uyên bác. Hãy giải thích cực kỳ CHI TIẾT, SÂU SẮC. Phân tích cặn kẽ bám sát vào tài liệu, có ví dụ minh họa và trình bày đẹp mắt bằng gạch đầu dòng để học sinh dễ đúc kết kiến thức."
            if is_chat_mode else
            "Bạn là AI tạo dữ liệu. Tuân thủ tuyệt đối định dạng JSON được yêu cầu, KHÔNG giải thích dông dài."
        )
        
        chat_completion = groq_client.chat.completions.create(
            messages=[
                {"role": "system", "content": sys_msg},
                {"role": "user", "content": prompt}
            ],
            model=GROQ_MODEL,
            # Sử dụng nhiệt độ được truyền vào (cao = sáng tạo, thấp = an toàn máy móc)
            temperature=temp, 
        )
        return chat_completion.choices[0].message.content
    except Exception as e:
        raise Exception(f"Lỗi API Groq: {str(e)}")

# 🛡️ MÀNG LỌC BẢO VỆ 1: Chống vỡ file JSON
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

# 🛡️ MÀNG LỌC BẢO VỆ 2: QUÉT DIỆN RỘNG (Khắc phục lỗi chỉ lấy câu hỏi đoạn đầu)
def get_active_context(query: str, user_id: str, k_needed: int = 15):
    if not os.path.exists(VECTOR_DB_PATH): return ""
    vector_db = FAISS.load_local(VECTOR_DB_PATH, embeddings, allow_dangerous_deserialization=True)
    
    # Lấy hẳn 50 đoạn (chunks) để tăng tỷ lệ trúng các chương khác nhau ở giữa và cuối sách
    docs = vector_db.similarity_search(query, k=50) 
    
    try:
        res = supabase.table("uploaded_files").select("filename").eq("user_id", user_id).execute()
        active_files = [r['filename'] for r in res.data]
    except: active_files = []
        
    if not active_files: return ""
    
    # Lọc bỏ tài liệu đã xóa
    valid_docs = [d for d in docs if d.metadata.get("filename") in active_files]
    
    # Trả về k_needed đoạn (Ví dụ: 15 đoạn = 15.000 chữ) để AI đọc toàn bộ
    return "\n\n---\n\n".join([doc.page_content for doc in valid_docs[:k_needed]])


# ================= API ENDPOINTS =================

@app.get("/")
async def root():
    return {"status": "online", "message": "AI Tutor Backend đang hoạt động đỉnh cao! 🚀"}

# --- API: GIỌNG NÓI EDGE TTS ---
@app.get("/api/tts")
async def text_to_speech(text: str):
    try:
        # Giọng nữ miền Nam (HoaiMy) siêu tự nhiên, đọc có ngắt nghỉ cảm xúc
        communicate = edge_tts.Communicate(text, "vi-VN-HoaiMyNeural", rate="+5%") 
        audio_data = b""
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio_data += chunk["data"]
        return StreamingResponse(io.BytesIO(audio_data), media_type="audio/mpeg")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- API: TẢI FILE PDF ---
@app.post("/api/upload")
async def upload_pdf(file: UploadFile = File(...), user_id: str = Form(...)): 
    try:
        content = await file.read()
        pdf_reader = PyPDF2.PdfReader(io.BytesIO(content))
        full_text = ""
        for page in pdf_reader.pages:
            extracted = page.extract_text()
            if extracted: full_text += extracted + "\n"

        chunks = text_splitter.split_text(full_text)
        metadatas = [{"filename": file.filename} for _ in chunks]
        
        if os.path.exists(VECTOR_DB_PATH):
            vector_db = FAISS.load_local(VECTOR_DB_PATH, embeddings, allow_dangerous_deserialization=True)
            vector_db.add_texts(chunks, metadatas=metadatas) 
        else:
            vector_db = FAISS.from_texts(chunks, embeddings, metadatas=metadatas) 
        vector_db.save_local(VECTOR_DB_PATH)

        supabase.table("uploaded_files").insert({"user_id": user_id, "filename": file.filename}).execute()
        return {"status": "success", "message": f"Đã học thêm file {file.filename}!"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/files/{user_id}")
async def get_uploaded_files(user_id: str):
    response = supabase.table("uploaded_files").select("*").eq("user_id", user_id).order("upload_date", desc=True).execute()
    return [{"id": r['id'], "filename": r['filename'], "date": r['upload_date']} for r in response.data]

@app.delete("/api/files/{file_id}")
async def delete_file_history(file_id: int):
    supabase.table("uploaded_files").delete().eq("id", file_id).execute()
    return {"status": "success", "message": "Đã xóa file khỏi lịch sử"}

@app.delete("/api/files/reset/{user_id}")
async def reset_ai_brain(user_id: str):
    if os.path.exists(VECTOR_DB_PATH): shutil.rmtree(VECTOR_DB_PATH)
    supabase.table("uploaded_files").delete().eq("user_id", user_id).execute()
    return {"status": "success", "message": "Đã tẩy não AI thành công!"}

# --- API: CHAT VỚI AI ---
# --- API: CHAT VỚI AI (Đã nâng cấp trả lời chuyên sâu) ---
@app.post("/api/chat")
async def chat_with_ai(request: ChatRequest):
    try:
        # Tăng gấp đôi lượng kiến thức đọc vào (k_needed=10) để AI hiểu sâu bối cảnh
        context = get_active_context(request.message, request.user_id, k_needed=10)
        if not context and not os.path.exists(VECTOR_DB_PATH):
            return {"status": "success", "data": {"role": "assistant", "content": "Vui lòng tải tài liệu PDF lên trước nhé! 📚"}}
            
        prompt = f"""
        TÀI LIỆU HỌC TẬP: 
        {context}
        
        CÂU HỎI CỦA HỌC SINH: {request.message}
        
        YÊU CẦU DÀNH CHO GIA SƯ:
        1. Trả lời trực tiếp, CHI TIẾT và SÂU SẮC vào vấn đề học sinh hỏi. Không trả lời chung chung.
        2. Bắt buộc phải trích xuất các định nghĩa, đặc điểm, số liệu hoặc ví dụ từ TÀI LIỆU để dẫn chứng cho câu trả lời.
        3. Trình bày rõ ràng theo từng ý (dùng gạch đầu dòng, in đậm các từ khóa) để học sinh dễ dàng ghi chép vào sổ tay.
        4. Nếu tài liệu chưa đủ thông tin, hãy bổ sung thêm kiến thức mở rộng của bạn để bài giảng hoàn thiện nhất.
        """
        
        # Gọi AI và KÍCH HOẠT CHẾ ĐỘ CHAT (is_chat_mode=True)
        raw_text = call_groq(prompt, is_chat_mode=True)
        return {"status": "success", "data": {"role": "assistant", "content": raw_text}}
    except Exception as e:
        return {"status": "success", "data": {"role": "assistant", "content": f"Hệ thống báo lỗi: {str(e)}"}}





@app.post("/api/quiz")
async def generate_quiz(request: Request): 
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
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
            difficulty_instruction = "MỨC ĐỘ CỰC KHÓ: Câu hỏi suy luận logic, phân tích. Đáp án sai phải viết CỰC KỲ TINH VI, dùng từ giống hệt tài liệu để làm bẫy."

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

# --- API: TẠO FLASHCARD (MỞ RỘNG DIỆN QUÉT) ---
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

# --- API: TẠO LỘ TRÌNH (MỞ RỘNG DIỆN QUÉT) ---
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

# --- CÁC API HỆ THỐNG (LƯU ĐIỂM, LỊCH SỬ, GHI CHÚ, THỐNG KÊ, USER...) ---
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

def hash_password(password: str): return hashlib.sha256(password.encode()).hexdigest()

@app.post("/api/register")
async def register(request: AuthRequest):
    try:
        res = supabase.table("users").select("*").eq("username", request.username).execute()
        if res.data: raise HTTPException(status_code=400, detail="Tên đăng nhập đã tồn tại!")
        supabase.table("users").insert({"username": request.username, "password": hash_password(request.password)}).execute()
        return {"status": "success", "message": "Đăng ký thành công!"}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/login")
async def login(request: AuthRequest):
    res = supabase.table("users").select("*").eq("username", request.username).eq("password", hash_password(request.password)).execute()
    if res.data: return {"status": "success", "username": res.data[0]['username']}
    raise HTTPException(status_code=400, detail="Sai tên đăng nhập hoặc mật khẩu!")
    

# --- API: BÁO CÁO ĐIỂM YẾU & TẠO QUIZ KHẮC PHỤC ---
@app.post("/api/analyze_weakness")
async def analyze_weakness(request: WeaknessRequest):
    try:
        if not request.wrong_questions:
            return {"status": "success", "data": {"report": "🎉 Tuyệt vời! Bạn đã làm đúng 100% không sai câu nào.", "quiz": []}}
            
        # Nối các câu sai thành từ khóa để AI tìm đúng chương/phần slide bị hổng
        search_query = " ".join(request.wrong_questions)
        context = get_active_context(search_query, request.user_id, k_needed=10)
        
        prompt = f"""
        Học sinh vừa làm bài thi và bị TÍNH TOÁN SAI ở các câu hỏi sau:
        {request.wrong_questions}
        
        TÀI LIỆU HỌC TẬP:
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
        
        # Lọc bảo vệ JSON cho mảng quiz
        valid_quiz = extract_json_array(parsed_data.get("quiz", []), ["question", "options", "answer"])
        
        return {
            "status": "success", 
            "data": {
                "report": parsed_data.get("report", "Không thể tạo báo cáo lúc này."),
                "quiz": valid_quiz
            }
        }
    except Exception as e:
        print(f"Lỗi AI phân tích: {str(e)}")
        return {"status": "error", "message": "Lỗi hệ thống phân tích."}