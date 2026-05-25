from fastapi import APIRouter, Request
import json
import random
from models import WeaknessRequest
from core import get_active_context, call_groq, extract_json_array, supabase
from datetime import datetime

router = APIRouter()

@router.post("/api/quiz")
async def generate_quiz(request: Request): 
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        num_questions = data.get("num_questions", 5) 
        difficulty = data.get("difficulty", "Trung bình")
        
        search_query = "Tất cả các định nghĩa, khái niệm, đặc điểm, công thức, nguyên lý, ví dụ và ứng dụng trong toàn bộ tài liệu"
        context = get_active_context(search_query, user_id, notebook_id, k_needed=15)
        
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
        time_str = datetime.now().strftime("%H:%M %d/%m")
        deck_title = f"Đề {difficulty} ({time_str})"
        res = supabase.table("quiz_decks").insert({
            "user_id": user_id, 
            "notebook_id": int(notebook_id), 
            "difficulty": difficulty,
            "title": deck_title,
            "questions": quiz_data # 👈 NHÉT NGUYÊN MẢNG JSON VÀO ĐÂY
        }).execute()

        return {"status": "success", "deck_id": res.data[0]['id'], "data": quiz_data}
    except Exception as e:
        return {"data": [{"question": "Hệ thống bị gián đoạn. Xin hãy thử lại!", "options": ["OK"], "answer": "OK"}]}

@router.get("/api/quiz/history/{notebook_id}")
async def get_quiz_history(notebook_id: int, user_id: str):
    res = supabase.table("quiz_decks").select("id, title, difficulty, created_at").eq("notebook_id", notebook_id).eq("user_id", user_id).order("created_at", desc=True).execute()
    return {"status": "success", "data": res.data}

@router.get("/api/quiz/deck/{deck_id}")
async def get_quiz_deck(deck_id: int):
    res = supabase.table("quiz_decks").select("questions").eq("id", deck_id).execute()
    return {"status": "success", "data": res.data[0]['questions']}


# ==================== KHU VỰC ĐIỂM YẾU ====================
@router.post("/api/analyze_weakness")
async def analyze_weakness(request: WeaknessRequest):
    try:
        if not request.wrong_questions:
            return {"status": "success", "data": {"report": "🎉 Tuyệt vời! Bạn đã làm đúng 100% không sai câu nào.", "quiz": []}}
        search_query = " ".join(request.wrong_questions)
        context = get_active_context(search_query, request.user_id, request.notebook_id, k_needed=10)
        prompt = f"""
        Học sinh sai: {request.wrong_questions}
        TÀI LIỆU: {context}
        Trả JSON: {{"report": "Phân tích...", "quiz": [{{"question": "...", "options": ["A", "B"], "answer": "A"}}]}}
        """
        raw_text = call_groq(prompt).replace("```json", "").replace("```", "").strip()
        parsed_data = json.loads(raw_text)
        valid_quiz = extract_json_array(parsed_data.get("quiz", []), ["question", "options", "answer"])
        return {"status": "success", "data": {"report": parsed_data.get("report", ""), "quiz": valid_quiz}}
    except Exception as e:
        return {"status": "error", "message": "Lỗi hệ thống."}


# ==================== KHU VỰC FLASHCARDS ====================
@router.post("/api/flashcards")
async def generate_flashcards(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        num_cards = data.get("num_cards", 5)

        context = get_active_context("Các thuật ngữ", user_id, str(notebook_id), k_needed=15)
        if not context: 
            return {"data": [{"term": "Chưa tải PDF", "definition": "Vui lòng tải tài liệu"}]}
            
        prompt = f"Dựa vào tài liệu tạo {num_cards} flashcard. TÀI LIỆU: {context}\nTrả JSON mảng: [{{\"term\": \"A\", \"definition\": \"B\"}}]"
        raw_text = call_groq(prompt).replace("```json", "").replace("```", "").strip()
        flashcards = extract_json_array(json.loads(raw_text), ["term", "definition"])
        
        # LƯU BỘ THẺ MỚI
        time_str = datetime.now().strftime("%H:%M %d/%m")
        deck_title = f"Bộ thẻ {time_str} ({num_cards} từ)"
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
async def get_flashcard_deck(deck_id: int):
    res = supabase.table("flashcard_decks").select("cards").eq("id", deck_id).execute()
    return {"status": "success", "data": res.data[0]['cards']} 


# ==================== KHU VỰC ROADMAP ====================
@router.post("/api/roadmap")
async def generate_roadmap(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        
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