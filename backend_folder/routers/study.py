from fastapi import APIRouter, Request
import json
import random
from models import WeaknessRequest
# 🚀 ĐÃ XÓA VECTOR_DB_ROOT, FAISS và embeddings vì không cần dùng local nữa
from core import get_active_context, call_groq, extract_json_array, supabase
from datetime import datetime

router = APIRouter()

# 🚀 NÂNG CẤP: HÀM BỐC TÀI LIỆU NGẪU NHIÊN TRỰC TIẾP TỪ SUPABASE CLOUD
def get_random_context(user_id: str, notebook_id: str, k_needed: int = 20):
    try:
        # Lấy toàn bộ các đoạn văn thuộc về user_id và notebook_id này trực tiếp từ bảng 'documents'
        res = supabase.table("documents").select("content, metadata").eq("metadata->>user_id", user_id).eq("metadata->>notebook_id", str(notebook_id)).execute()
        
        all_docs = res.data
        if all_docs:
            # Xáo trộn và bốc ngẫu nhiên k đoạn văn (chunk)
            sampled_docs = random.sample(all_docs, min(k_needed, len(all_docs)))
            
            formatted_docs = []
            for d in sampled_docs:
                page = d.get("metadata", {}).get("page", "?")
                content = d.get("content", "")
                formatted_docs.append(f"Trang {page}: {content}")
                
            return "\n\n".join(formatted_docs)
    except Exception as e:
        print(f"Lỗi lấy context ngẫu nhiên từ Cloud: {e}")
    return ""


# ==================== KHU VỰC QUIZ ====================
@router.post("/api/quiz")
async def generate_quiz(request: Request): 
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        num_questions = int(data.get("num_questions", 5))
        difficulty = data.get("difficulty", "Trung bình")
        
        # 1. TẠO SỔ ĐEN
        forbidden_concepts = []
        try:
            history_res = supabase.table("quiz_decks").select("questions").eq("notebook_id", int(notebook_id)).eq("user_id", user_id).order("created_at", desc=True).limit(5).execute()
            if history_res.data:
                for deck in history_res.data:
                    for q in deck.get("questions", []):
                        if "concept" in q:
                            forbidden_concepts.append(q["concept"])
            forbidden_concepts = list(set(forbidden_concepts))
        except:
            pass
            
        forbidden_str = ", ".join(forbidden_concepts) if forbidden_concepts else "Chưa có"

        # 2. BỐC TÀI LIỆU
        k_size = min(12, num_questions * 2) 
        context = get_random_context(user_id, str(notebook_id), k_needed=k_size)
        
        if not context:
            return {"data": [{"question": "Bạn chưa tải file PDF!", "options": ["Đã hiểu"], "answer": "Đã hiểu", "concept": "Lỗi", "source_page": "0", "explanation": "Vui lòng tải tài liệu."}]}
            
        # 3. TẠO LĂNG KÍNH NGẪU NHIÊN 
        focus_areas = [
            "ĐÀO SÂU vào các khái niệm phụ, định nghĩa nhỏ lẻ ít người để ý",
            "TÌM KIẾM các con số, mốc thời gian, số liệu thống kê hoặc tỷ lệ phần trăm",
            "TẬP TRUNG vào nguyên lý hoạt động, cơ chế, hoặc các bước trong một quy trình",
            "KHAI THÁC các ví dụ thực tế, tình huống ứng dụng, hoặc ngoại lệ",
            "PHÂN TÍCH sự khác biệt, ưu điểm, nhược điểm, hoặc so sánh",
            "BỐC NGẪU NHIÊN các chi tiết râu ria nằm ở cuối mỗi đoạn văn"
        ]
        focus_instruction = random.choice(focus_areas)
        random_seed = random.randint(10000, 99999) 

        difficulty_instruction = ""
        if difficulty == "Dễ":
            difficulty_instruction = "MỨC ĐỘ DỄ: Chỉ hỏi trực tiếp vào định nghĩa."
        elif difficulty == "Trung bình":
            difficulty_instruction = "MỨC ĐỘ TRUNG BÌNH: CẤM hỏi kiểu định nghĩa. Phải đưa ra đặc điểm, ví dụ."
        elif difficulty == "Khó":
            difficulty_instruction = "MỨC ĐỘ KHÓ: Bắt buộc dùng cấu trúc 'Phát biểu nào sau đây ĐÚNG/SAI?'. Đáp án bẫy cực kỳ tinh vi."
        elif difficulty == "Phòng thi ảo":
            difficulty_instruction = "TRỘN LẪN ĐỘ KHÓ DỄ - TRUNG BÌNH - KHÓ."

        prompt = f"""
        Bạn là chuyên gia khảo thí. Dựa vào TÀI LIỆU sau, tạo {num_questions} câu hỏi trắc nghiệm.
        TÀI LIỆU: {context}
        
        CHÚ Ý ĐỘ KHÓ: {difficulty_instruction}
        
        ⛔ MỆNH LỆNH LÀM MỚI (Mã hạt giống: {random_seed}):
        1. GÓC NHÌN LẦN NÀY: BẠN BẮT BUỘC PHẢI {focus_instruction}. TUYỆT ĐỐI KHÔNG hỏi các tiêu đề lớn to tát.
        2. HẠN CHẾ TRÙNG LẶP: Học sinh đã làm các chủ đề này rồi: [{forbidden_str}]. Hãy cố gắng né chúng ra!
        
        YÊU CẦU JSON BẮT BUỘC: Trả về CHỈ 1 MẢNG JSON thuần túy.
        [
          {{
            "question": "Nội dung?", 
            "options": ["A", "B", "C", "D"], 
            "answer": "A",
            "concept": "Tên khái niệm (Ngắn gọn)",
            "source_page": "Trang chứa thông tin",
            "explanation": "Giải thích chi tiết."
          }}
        ]
        """
        
        raw_text = call_groq(prompt, is_chat_mode=False, temp=0.85).replace("```json", "").replace("```", "").strip()
        quiz_data = extract_json_array(json.loads(raw_text), ["question", "options", "answer", "concept", "source_page", "explanation"]) 
        
        deck_title = f"Đề {difficulty} ({datetime.now().strftime('%H:%M %d/%m')})"
        res = supabase.table("quiz_decks").insert({
            "user_id": user_id, "notebook_id": int(notebook_id), "difficulty": difficulty, "title": deck_title, "questions": quiz_data 
        }).execute()

        return {"status": "success", "deck_id": res.data[0]['id'], "data": quiz_data}
    except Exception as e:
        return {"data": [{"question": "Hệ thống bị gián đoạn.", "options": ["OK"], "answer": "OK", "concept": "Lỗi", "source_page": "0", "explanation": str(e)}]}

# ==================== CÁC API LỊCH SỬ QUIZ ====================
@router.get("/api/quiz/history/{notebook_id}")
async def get_quiz_history(notebook_id: int, user_id: str):
    res = supabase.table("quiz_decks").select("id, title, difficulty, created_at").eq("notebook_id", notebook_id).eq("user_id", user_id).order("created_at", desc=True).execute()
    return {"status": "success", "data": res.data}

@router.get("/api/quiz/deck/{deck_id}")
async def get_quiz_deck(deck_id: int, user_id: str):
    try:
        res = supabase.table("quiz_decks").select("questions").eq("id", deck_id).eq("user_id", user_id).execute()
        return {"status": "success", "data": res.data[0]['questions']} if res.data else {"status": "error", "message": "Không tìm thấy."}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# ==================== KHU VỰC ĐIỂM YẾU ====================
@router.post("/api/analyze_weakness")
async def analyze_weakness(request: WeaknessRequest):
    try:
        if not request.wrong_questions:
            return {"status": "success", "data": {"report": "Tuyệt vời!", "quiz": []}}
        search_query = " ".join(request.wrong_questions)
        context = get_active_context(search_query, request.user_id, request.notebook_id, k_needed=15)
        
        prompt = f"""
        Học sinh sai các câu hỏi liên quan: {request.wrong_questions}
        TÀI LIỆU CƠ SỞ: {context}
        Trả JSON: {{"report": "Phân tích theo khái niệm...", "quiz": [{{"question": "...", "options": ["A", "B"], "answer": "A", "concept": "...", "source_page": "...", "explanation": "..."}}]}}
        """
        raw_text = call_groq(prompt).replace("```json", "").replace("```", "").strip()
        parsed_data = json.loads(raw_text)
        valid_quiz = extract_json_array(parsed_data.get("quiz", []), ["question", "options", "answer", "concept", "source_page", "explanation"])
        return {"status": "success", "data": {"report": parsed_data.get("report", ""), "quiz": valid_quiz}}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# ==================== KHU VỰC FLASHCARDS ====================
@router.post("/api/flashcards")
async def generate_flashcards(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        num_cards = int(data.get("num_cards", 5))

        # 1. TẠO SỔ ĐEN
        forbidden_terms = []
        try:
            history_res = supabase.table("flashcard_decks").select("cards").eq("notebook_id", int(notebook_id)).eq("user_id", user_id).order("created_at", desc=True).limit(5).execute()
            if history_res.data:
                for deck in history_res.data:
                    for c in deck.get("cards", []):
                        if "term" in c:
                            forbidden_terms.append(c["term"])
            forbidden_terms = list(set(forbidden_terms))
        except:
            pass
            
        forbidden_str = ", ".join(forbidden_terms) if forbidden_terms else "Chưa có"

        # 2. BỐC TÀI LIỆU
        k_size = min(15, num_cards * 2)
        context = get_random_context(user_id, str(notebook_id), k_needed=k_size)
        
        if not context: 
            return {"data": [{"term": "Chưa tải PDF", "definition": "Vui lòng tải tài liệu"}]}
            
        # 3. LĂNG KÍNH NGẪU NHIÊN 
        focus_areas = [
            "Tập trung vào các thuật ngữ phụ, ít nổi bật",
            "Tìm các con số quan trọng, năm, tỷ lệ phần trăm",
            "Tìm các tên người, tác giả, hoặc công ty được nhắc đến",
            "Khai thác các định nghĩa ngách ở cuối các đoạn văn"
        ]
        focus_instruction = random.choice(focus_areas)
        random_seed = random.randint(10000, 99999)

        prompt = f"""
        Dựa vào TÀI LIỆU sau, tạo {num_cards} flashcard chứa thuật ngữ và định nghĩa.
        TÀI LIỆU: {context}
        
        ⛔ MỆNH LỆNH ĐỔI MỚI (Mã hạt giống: {random_seed}):
        1. GÓC NHÌN: BẠN HÃY {focus_instruction}. KHÔNG ĐƯỢC chỉ bốc các tiêu đề lớn ở đầu bài.
        2. HẠN CHẾ TRÙNG LẶP: Đã học các thuật ngữ này: [{forbidden_str}]. Hãy cố gắng tìm từ mới!
        
        Trả JSON mảng thuần túy: [{{"term": "A", "definition": "B"}}]
        """
        
        raw_text = call_groq(prompt, is_chat_mode=False, temp=0.9).replace("```json", "").replace("```", "").strip() 
        flashcards = extract_json_array(json.loads(raw_text), ["term", "definition"])
        
        current_time = datetime.now().isoformat()
        for card in flashcards:
            card.update({"ease": 2.5, "interval": 0, "reps": 0, "lapses": 0, "due_date": current_time, "last_reviewed": None})
        
        deck_title = f"Bộ Flashcard ({datetime.now().strftime('%H:%M %d/%m')})"
        res = supabase.table("flashcard_decks").insert({
            "user_id": user_id, "notebook_id": int(notebook_id), "title": deck_title, "cards": flashcards
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
        return {"status": "success", "data": res.data[0]['cards']} if res.data else {"status": "error", "message": "Không tìm thấy."}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@router.put("/api/flashcards/deck/{deck_id}")
async def sync_flashcard_progress(deck_id: int, request: Request):
    try:
        data = await request.json()
        supabase.table("flashcard_decks").update({"cards": data.get("cards")}).eq("id", deck_id).eq("user_id", data.get("user_id")).execute()
        return {"status": "success", "message": "Đã đồng bộ!"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# ==================== KHU VỰC ROADMAP ====================
@router.post("/api/roadmap")
async def generate_roadmap(request: Request):
    try:
        data = await request.json()
        search_query = "Tóm tắt nội dung chính, mục lục, các chương, chủ đề cốt lõi"
        context = get_active_context(search_query, data.get("user_id", ""), data.get("notebook_id", ""), k_needed=15)
        
        if not context: return {"data": [{"day": "Lỗi", "title": "Chưa có PDF", "tasks": ["Tải tài liệu lên!"]}]}
            
        prompt = f"Dựa vào TÀI LIỆU sau, tạo Lộ trình học 5 giai đoạn.\\nTÀI LIỆU: {context}\\nTrả về 1 MẢNG JSON.\\n[{{\"day\": \"Giai đoạn 1\", \"title\": \"...\", \"tasks\": [\"A\"]}}]"
        raw_text = call_groq(prompt).replace("```json", "").replace("```", "").strip()
        roadmap_data = extract_json_array(json.loads(raw_text), ["day", "title", "tasks"]) 
        return {"data": roadmap_data}
    except Exception:
        return {"data": [{"day": "Lỗi hệ thống", "title": "AI từ chối định dạng", "tasks": ["Xin bấm tạo lại!"]}]}