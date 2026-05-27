from fastapi import APIRouter, Request
import json
import random
import os
from models import WeaknessRequest
from core import get_active_context, call_groq, extract_json_array, supabase, VECTOR_DB_ROOT, embeddings
from langchain_community.vectorstores import FAISS
from datetime import datetime

router = APIRouter()

# 🚀 NÂNG CẤP LỚN: HÀM BỐC TÀI LIỆU NGẪU NHIÊN CHỐNG LẶP CÂU HỎI
def get_random_context(user_id: str, notebook_id: str, k_needed: int = 20):
    user_vector_path = os.path.join(VECTOR_DB_ROOT, str(user_id), str(notebook_id))
    if not os.path.exists(os.path.join(user_vector_path, "index.faiss")):
        return ""
        
    try:
        vector_db = FAISS.load_local(user_vector_path, embeddings, allow_dangerous_deserialization=True)
        res = supabase.table("uploaded_files").select("filename").eq("user_id", str(user_id)).eq("notebook_id", int(notebook_id)).execute()
        active_files = [r['filename'] for r in res.data]
        
        # Gom toàn bộ các đoạn văn thuộc file của dự án này
        all_docs = [doc for doc in vector_db.docstore._dict.values() if doc.metadata.get("filename") in active_files]
        
        if all_docs:
            # Xáo trộn và bốc ngẫu nhiên k đoạn văn bất kỳ (Không thèm quan tâm Semantic Search)
            sampled_docs = random.sample(all_docs, min(k_needed, len(all_docs)))
            return "\n\n".join([f"Trang {d.metadata.get('page')}: {d.page_content}" for d in sampled_docs])
    except Exception as e:
        print(f"Lỗi lấy context ngẫu nhiên: {e}")
    return ""


# ==================== KHU VỰC QUIZ ====================
@router.post("/api/quiz")
async def generate_quiz(request: Request): 
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        num_questions = data.get("num_questions", 5) 
        difficulty = data.get("difficulty", "Trung bình")
        
        # 🛡️ Dùng hàm Random Context để Quiz luôn có câu hỏi mới
        context = get_random_context(user_id, str(notebook_id), k_needed=20)
        
        if not context:
            return {"data": [{"question": "Bạn chưa tải file PDF hoặc file đã bị xóa sạch! Hãy tải tài liệu mới lên nhé.", "options": ["Đã hiểu"], "answer": "Đã hiểu", "concept": "Lỗi", "source_page": "0", "explanation": "Vui lòng tải tài liệu."}]}
            
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
        elif difficulty == "Phòng thi ảo":
            difficulty_instruction = """
            - MỨC ĐỘ TỔNG HỢP (PHÒNG THI CHÍNH THỨC):
            BẮT BUỘC TRỘN LẪN độ khó cho toàn bộ đề thi theo tỷ lệ sau:
            1. Nhóm DỄ (30% số câu): Hỏi trực tiếp định nghĩa cơ bản, đáp án sai dễ loại trừ.
            2. Nhóm TRUNG BÌNH (40% số câu): CẤM hỏi định nghĩa. Hãy hỏi về ví dụ, đặc điểm, hoặc nguyên lý hoạt động.
            3. Nhóm KHÓ (30% số câu): BẮT BUỘC dùng cấu trúc "Phát biểu nào sau đây là ĐÚNG (hoặc SAI)?". Các đáp án bẫy phải cực kỳ tinh vi.
            """

        prompt = f"""
        Bạn là chuyên gia khảo thí. Dựa vào TÀI LIỆU NGẪU NHIÊN sau, tạo {num_questions} câu hỏi trắc nghiệm.
        TÀI LIỆU: {context}
        
        CHÚ Ý ĐỘ KHÓ: 
        {difficulty_instruction}
        
        YÊU CẦU JSON BẮT BUỘC: Trả về CHỈ 1 MẢNG JSON thuần túy. 
        Cấu trúc mẫu chuẩn:
        [
          {{
            "question": "Nội dung câu hỏi?", 
            "options": ["A", "B", "C", "D"], 
            "answer": "A",
            "concept": "Tên khái niệm (Ngắn gọn)",
            "source_page": "Trang chứa thông tin",
            "explanation": "Giải thích chi tiết."
          }}
        ]
        
        LƯU Ý: Trường "answer" phải CHÉP LẠI Y HỆT NỘI DUNG CHỮ của đáp án đúng.
        """
        
        raw_text = call_groq(prompt, is_chat_mode=False, temp=0.8).replace("```json", "").replace("```", "").strip()
        
        required_keys = ["question", "options", "answer", "concept", "source_page", "explanation"]
        quiz_data = extract_json_array(json.loads(raw_text), required_keys) 
        
        time_str = datetime.now().strftime("%H:%M %d/%m")
        deck_title = f"Đề {difficulty} ({time_str})"
        res = supabase.table("quiz_decks").insert({
            "user_id": user_id, 
            "notebook_id": int(notebook_id), 
            "difficulty": difficulty,
            "title": deck_title,
            "questions": quiz_data 
        }).execute()

        return {"status": "success", "deck_id": res.data[0]['id'], "data": quiz_data}
    except Exception as e:
        return {"data": [{"question": "Hệ thống bị gián đoạn. Xin hãy thử lại!", "options": ["OK"], "answer": "OK", "concept": "Lỗi", "source_page": "0", "explanation": str(e)}]}

@router.get("/api/quiz/history/{notebook_id}")
async def get_quiz_history(notebook_id: int, user_id: str):
    res = supabase.table("quiz_decks").select("id, title, difficulty, created_at").eq("notebook_id", notebook_id).eq("user_id", user_id).order("created_at", desc=True).execute()
    return {"status": "success", "data": res.data}

@router.get("/api/quiz/deck/{deck_id}")
async def get_quiz_deck(deck_id: int, user_id: str):
    try:
        res = supabase.table("quiz_decks").select("questions").eq("id", deck_id).eq("user_id", user_id).execute()
        if not res.data:
            return {"status": "error", "message": "Không tìm thấy bộ đề."}
        return {"status": "success", "data": res.data[0]['questions']}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# ==================== KHU VỰC ĐIỂM YẾU ====================
@router.post("/api/analyze_weakness")
async def analyze_weakness(request: WeaknessRequest):
    try:
        if not request.wrong_questions:
            return {"status": "success", "data": {"report": "🎉 Tuyệt vời! Bạn đã nắm vững 100% các khái niệm trong bài test này.", "quiz": []}}
            
        search_query = " ".join(request.wrong_questions)
        context = get_active_context(search_query, request.user_id, request.notebook_id, k_needed=15)
        
        prompt = f"""
        Học sinh vừa làm sai các câu hỏi liên quan đến nội dung sau: 
        {request.wrong_questions}
        
        TÀI LIỆU CƠ SỞ: {context}
        
        YÊU CẦU BẮT BUỘC CỦA CHUYÊN GIA SƯ PHẠM:
        1. "report": Phân tích gộp các lỗi sai theo NHÓM KHÁI NIỆM (Concept).
        2. "quiz": Tạo ra 3-5 câu hỏi trắc nghiệm mới tinh tập trung XÓA MÙ KHOẢNG TRỐNG KIẾN THỨC.
        
        Trả đúng JSON: 
        {{
          "report": "Phân tích theo khái niệm...", 
          "quiz": [
            {{
              "question": "...", 
              "options": ["A", "B"], 
              "answer": "A", 
              "concept": "Tên khái niệm", 
              "source_page": "Trang X", 
              "explanation": "..."
            }}
          ]
        }}
        """
        raw_text = call_groq(prompt).replace("```json", "").replace("```", "").strip()
        parsed_data = json.loads(raw_text)
        
        required_keys = ["question", "options", "answer", "concept", "source_page", "explanation"]
        valid_quiz = extract_json_array(parsed_data.get("quiz", []), required_keys)
        
        return {"status": "success", "data": {"report": parsed_data.get("report", ""), "quiz": valid_quiz}}
    except Exception as e:
        return {"status": "error", "message": f"Lỗi phân tích: {str(e)}"}

# ==================== KHU VỰC FLASHCARDS ====================
@router.post("/api/flashcards")
async def generate_flashcards(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        num_cards = data.get("num_cards", 5)

        # 🛡️ Dùng hàm Random Context để Flashcard luôn lấy các khái niệm mới
        context = get_random_context(user_id, str(notebook_id), k_needed=20)
        
        if not context: 
            return {"data": [{"term": "Chưa tải PDF", "definition": "Vui lòng tải tài liệu"}]}
            
        prompt = f"""
        Dựa vào TÀI LIỆU NGẪU NHIÊN sau, tạo {num_cards} flashcard chứa thuật ngữ và định nghĩa.
        TÀI LIỆU: {context}
        
        CHÚ Ý ĐẶC BIỆT:
        - TUYỆT ĐỐI KHÔNG lặp lại những khái niệm quen thuộc. Hãy bám vào đoạn tài liệu ngẫu nhiên trên để tìm các ý mới.
        - Trả JSON mảng thuần túy: [{{"term": "A", "definition": "B"}}]
        """
        
        # Tăng nhiệt độ (Temp) lên 0.9 để kích thích AI dùng từ ngữ đa dạng hơn
        raw_text = call_groq(prompt, is_chat_mode=False, temp=0.9).replace("```json", "").replace("```", "").strip() 
        flashcards = extract_json_array(json.loads(raw_text), ["term", "definition"])
        
        current_time = datetime.now().isoformat()
        for card in flashcards:
            card.update({
                "ease": 2.5,        
                "interval": 0,      
                "reps": 0,          
                "lapses": 0,        
                "due_date": current_time, 
                "last_reviewed": None
            })
        
        time_str = datetime.now().strftime("%H:%M %d/%m")
        deck_title = f"Bộ Flashcard ({time_str})"
        res = supabase.table("flashcard_decks").insert({
            "user_id": user_id, 
            "notebook_id": int(notebook_id), 
            "title": deck_title,
            "cards": flashcards
        }).execute()
            
        return {"status": "success", "deck_id": res.data[0]['id'], "data": flashcards}
    except Exception as e: 
        return {"data": [{"term": "Lỗi", "definition": str(e)}]}
    
@router.get("/api/flashcards/history/{notebook_id}")
async def get_flashcard_history(notebook_id: int, user_id: str):
    res = supabase.table("flashcard_decks").select("id, title, created_at").eq("notebook_id", notebook_id).eq("user_id", user_id).order("created_at", desc=True).execute()
    return {"status": "success", "data": res.data}

@router.get("/api/flashcards/deck/{deck_id}")
async def get_flashcard_deck(deck_id: int, user_id: str):
    try:
        res = supabase.table("flashcard_decks").select("cards").eq("id", deck_id).eq("user_id", user_id).execute()
        if not res.data:
            return {"status": "error", "message": "Không tìm thấy bộ thẻ."}
        return {"status": "success", "data": res.data[0]['cards']} 
    except Exception as e:
        return {"status": "error", "message": str(e)}

@router.put("/api/flashcards/deck/{deck_id}")
async def sync_flashcard_progress(deck_id: int, request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id")
        updated_cards = data.get("cards")
        supabase.table("flashcard_decks").update({"cards": updated_cards}).eq("id", deck_id).eq("user_id", user_id).execute()
        return {"status": "success", "message": "Đã đồng bộ!"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# ==================== KHU VỰC ROADMAP ====================
@router.post("/api/roadmap")
async def generate_roadmap(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        
        # Roadmap vẫn giữ nguyên Semantic Search vì cần cái nhìn tổng quan toàn diện
        search_query = "Tóm tắt nội dung chính, mục lục, các chương, các phần, chủ đề cốt lõi toàn bài"
        context = get_active_context(search_query, user_id, data.get("notebook_id", ""), k_needed=15)
        
        if not context:
            return {"data": [{"day": "Lỗi", "title": "Chưa có PDF", "tasks": ["Tải tài liệu lên trang chủ trước nha!"]}]}
            
        prompt = f"Dựa vào TÀI LIỆU sau, tạo Lộ trình học 5 giai đoạn bao quát toàn bộ tài liệu.\nTÀI LIỆU: {context}\nYÊU CẦU: Trả về CHỈ 1 MẢNG JSON.\n[{{\"day\": \"Giai đoạn 1\", \"title\": \"Nắm bắt\", \"tasks\": [\"A\", \"B\"]}}]"
        raw_text = call_groq(prompt).replace("```json", "").replace("```", "").strip()
        roadmap_data = extract_json_array(json.loads(raw_text), ["day", "title", "tasks"]) 
        return {"data": roadmap_data}
    except Exception:
        return {"data": [{"day": "Lỗi hệ thống", "title": "AI từ chối định dạng", "tasks": ["Xin bấm tạo lại lộ trình!"]}]}