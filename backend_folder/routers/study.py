from fastapi import APIRouter, Request
import json
import random
from models import WeaknessRequest
# 🚀 ĐÃ XÓA VECTOR_DB_ROOT, FAISS và embeddings vì không cần dùng local nữa
from core import get_active_context, call_groq, extract_json_array, supabase, GROQ_API_KEYS
from datetime import datetime
from groq import Groq
from models import ScoreRequest
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
# ==================== KHU VỰC QUIZ ====================
# ==================== KHU VỰC QUIZ ====================
@router.post("/api/quiz")
async def generate_quiz(request: Request): 
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        num_questions = int(data.get("num_questions", 5))
        difficulty = data.get("difficulty", "Trung bình")
        quiz_type = data.get("quiz_type", "Trộn lẫn")
        focus_topic = data.get("focus_topic") # 🚀 NHẬN CHỦ ĐỀ BÀI HỌC TỪ APP
        
        # 1. TẠO SỔ ĐEN (Chống lặp câu hỏi)
        forbidden_concepts = []
        try:
            history_res = supabase.table("quiz_decks").select("questions").eq("notebook_id", int(notebook_id)).eq("user_id", user_id).order("created_at", desc=True).limit(5).execute()
            if history_res.data:
                for deck in history_res.data:
                    for q in deck.get("questions", []):
                        if "concept" in q:
                            forbidden_concepts.append(q["concept"])
            forbidden_concepts = list(set(forbidden_concepts))
        except: pass
            
        forbidden_str = ", ".join(forbidden_concepts) if forbidden_concepts else "Chưa có"

        # 2. BỐC TÀI LIỆU
        k_size = min(20, num_questions * 2) if difficulty == "Phòng thi ảo" else min(12, num_questions * 2)
        
        if focus_topic and difficulty != "Phòng thi ảo":
            search_query = f"Nội dung trọng tâm thuộc chủ đề: {focus_topic}"
            context = get_active_context(search_query, user_id, str(notebook_id), k_needed=k_size)
            focus_instruction = f"BÁM SÁT VÀO KIẾN THỨC CỦA CHỦ ĐỀ NÀY: {focus_topic}"
        else:
            context = get_random_context(user_id, str(notebook_id), k_needed=k_size)
            focus_areas = ["ĐÀO SÂU vào các khái niệm phụ", "TÌM KIẾM các con số, số liệu", "TẬP TRUNG vào nguyên lý", "KHAI THÁC ví dụ thực tế"]
            focus_instruction = random.choice(focus_areas)
        
        if not context:
            return {"data": [{"type": "multiple_choice", "question": "Bạn chưa tải file PDF!", "options": ["Đã hiểu"], "answer": "Đã hiểu", "concept": "Lỗi", "source_page": "0", "explanation": "Vui lòng tải tài liệu."}]}
            
        difficulty_instruction = "MỨC ĐỘ TRUNG BÌNH - KHÓ" if difficulty == "Phòng thi ảo" else f"MỨC ĐỘ: {difficulty}"

        # 🚀 HÀM NỘI BỘ GỌI AI THEO TỪNG ĐỢT (CHỐNG LỖI TOKEN)
        def call_ai_batch(target_num, type_instr):
            random_seed = random.randint(10000, 99999) 
            prompt = f"""
            Bạn là chuyên gia khảo thí. Dựa vào TÀI LIỆU sau, tạo ĐÚNG {target_num} câu hỏi.
            TÀI LIỆU: {context}
            
            CHÚ Ý ĐỘ KHÓ: {difficulty_instruction}
            
            ⛔ MỆNH LỆNH ĐỔI MỚI (Hạt giống: {random_seed}):
            1. GÓC NHÌN: {focus_instruction}. 
            2. HẠN CHẾ TRÙNG LẶP: Né các chủ đề này ra: [{forbidden_str}].
            
            🚀 YÊU CẦU LOẠI CÂU HỎI BẮT BUỘC:
            {type_instr}
            
            YÊU CẦU JSON: Trả về CHỈ 1 MẢNG JSON. KHÔNG BỌC TRONG DẤU ```json, KHÔNG GIẢI THÍCH THÊM.
            [
              {{
                "type": "multiple_choice",
                "question": "Nội dung câu hỏi?", 
                "options": ["A", "B", "C", "D"],
                "answer": "A", 
                "concept": "Tên khái niệm",
                "source_page": "Trang",
                "explanation": "Giải thích chi tiết."
              }}
            ]
            """
            try:
                raw_text = call_groq(prompt, is_chat_mode=False, temp=0.85).replace("```json", "").replace("```", "").strip()
                # Ép tìm và bóc tách mảng JSON
                start_idx = raw_text.find('[')
                end_idx = raw_text.rfind(']')
                if start_idx != -1 and end_idx != -1:
                    clean_json = raw_text[start_idx:end_idx+1]
                    return extract_json_array(json.loads(clean_json, strict=False), ["type", "question", "options", "answer", "concept", "source_page", "explanation"])
            except Exception as e:
                print(f"Lỗi AI Batch: {e}")
            return []

        # 3. CHIA NHÁNH LOGIC: PHÒNG THI ẢO VS LUYỆN TẬP THƯỜNG
        quiz_data = []
        
        if quiz_type == "Phòng thi ảo" or difficulty == "Phòng thi ảo":
            # ĐỢT 1: 20 CÂU TRẮC NGHIỆM
            instr_1 = 'BẠN PHẢI TẠO ĐÚNG 20 CÂU HỎI LOẠI "multiple_choice" (Trắc nghiệm 4 đáp án).'
            batch_1 = call_ai_batch(20, instr_1)
            
            # ĐỢT 2: 10 CÂU CÒN LẠI
            instr_2 = '''BẠN PHẢI TẠO ĐÚNG 10 CÂU HỎI THEO ĐÚNG THỨ TỰ SAU:
            - 4 CÂU ĐẦU: "true_false" (options luôn là ["Đúng", "Sai"]).
            - 4 CÂU TIẾP THEO: "fill_in_blank" (Đoạn văn đục 3-4 lỗ "___". "options" chứa 6-8 từ. "answer" nối bằng "|").
            - 2 CÂU CUỐI CÙNG: "short_answer" (Trả lời bằng 1-3 từ khóa. "options" để mảng rỗng []).'''
            batch_2 = call_ai_batch(10, instr_2)
            
            quiz_data = batch_1 + batch_2
        else:
            # XỬ LÝ CHO CÁC CHẾ ĐỘ LUYỆN TẬP THƯỜNG
            type_instruction = ""
            if quiz_type == "Trắc nghiệm": type_instruction = 'CHỈ TẠO câu hỏi "multiple_choice" (Trắc nghiệm 4 đáp án).'
            elif quiz_type == "Đúng/Sai": type_instruction = 'CHỈ TẠO câu hỏi "true_false" (options là ["Đúng", "Sai"]).'
            elif quiz_type == "Điền khuyết": type_instruction = 'CHỈ TẠO "fill_in_blank" (Đục 3-4 lỗ "___", answer nối bằng "|").'
            elif quiz_type == "Trả lời ngắn": type_instruction = 'CHỈ TẠO "short_answer" (Trả lời ngắn, options là []).'
            else: type_instruction = 'TRỘN LẪN ngẫu nhiên 4 loại: multiple_choice, true_false, fill_in_blank, short_answer.'
            
            quiz_data = call_ai_batch(num_questions, type_instruction)

        # Kiểm tra an toàn nếu AI lỗi hoàn toàn
        if not quiz_data:
            return {"data": [{"type": "multiple_choice", "question": "Hệ thống AI đang bị quá tải, vui lòng thử lại.", "options": ["OK"], "answer": "OK", "concept": "Lỗi", "source_page": "0", "explanation": "Lỗi API"}]}

        # 4. LƯU VÀO DATABASE
        deck_title = f"Đề {difficulty} ({datetime.now().strftime('%H:%M %d/%m')})"
        if focus_topic and difficulty != "Phòng thi ảo":
            deck_title = f"Đề Ôn Lộ Trình ({datetime.now().strftime('%H:%M')})"

        res = supabase.table("quiz_decks").insert({
            "user_id": user_id, "notebook_id": int(notebook_id), "difficulty": difficulty, "title": deck_title, "questions": quiz_data 
        }).execute()

        return {"status": "success", "deck_id": res.data[0]['id'], "data": quiz_data}
    except Exception as e:
        return {"data": [{"type": "multiple_choice", "question": "Hệ thống bị gián đoạn.", "options": ["OK"], "answer": "OK", "concept": "Lỗi", "source_page": "0", "explanation": str(e)}]}
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
# ==================== KHU VỰC ĐIỂM YẾU ====================
# ==================== KHU VỰC ĐIỂM YẾU ====================
@router.post("/api/analyze_weakness")
async def analyze_weakness(request: Request): 
    try:
        data = await request.json()
        user_id = data.get("user_id")
        notebook_id = data.get("notebook_id")
        wrong_questions = data.get("wrong_questions", [])
        correct_questions = data.get("correct_questions", []) 

        if not wrong_questions:
            return {"status": "success", "data": {"report": "🎉 Tuyệt vời! Bạn đã trả lời đúng tất cả các câu hỏi.", "quiz": []}}
            
        search_query = " ".join(wrong_questions)
        context = get_active_context(search_query, user_id, str(notebook_id), k_needed=15)
        
        prompt = f"""
        Bạn là một Gia sư AI xuất sắc. Hãy phân tích kết quả bài thi của học sinh:
        - Học sinh ĐÃ LÀM TỐT các chủ đề này: {correct_questions}
        - Học sinh LÀM SAI các câu hỏi này: {wrong_questions}
        
        TÀI LIỆU CƠ SỞ CHUYÊN MÔN: {context}
        
        YÊU CẦU BÁO CÁO (Trường "report" định dạng Markdown, BẮT BUỘC có 3 phần sau):
        ### 🌟 1. Những gì bạn đã làm được
        [Khen ngợi và chỉ ra những chủ đề học sinh đã nắm vững]
        
        ### ⚠️ 2. Phân tích lỗ hổng kiến thức
        [Phân tích chi tiết tại sao học sinh lại sai những câu kia. Giải thích bản chất đúng dựa vào tài liệu]
        
        ### 🎯 3. Lời khuyên & Mẹo khắc phục
        [Đưa ra chiến lược học tập hoặc mẹo ghi nhớ để không bao giờ sai lại phần này nữa]
        
        YÊU CẦU BÀI TẬP BỔ TRỢ (Trường "quiz"):
        Tạo 1 đến 3 câu hỏi trắc nghiệm MỚI TINH để học sinh thực hành lại ĐÚNG phần kiến thức bị sai.
        
        TRẢ VỀ DUY NHẤT 1 ĐỐI TƯỢNG JSON ĐÚNG CHUẨN NÀY:
        {{
            "report": "Nội dung báo cáo...",
            "quiz": [
                {{"type": "multiple_choice", "question": "...", "options": ["A", "B", "C", "D"], "answer": "A", "concept": "...", "source_page": "...", "explanation": "..."}}
            ]
        }}
        """
        
        raw_text = call_groq(prompt, temp=0.5)
        
        # 🚀 BỌC THÉP 1: ÉP TÌM ĐÚNG VÙNG CHỨA JSON (Chống AI nói nhảm thêm chữ ở ngoài)
        start_idx = raw_text.find('{')
        end_idx = raw_text.rfind('}')
        if start_idx != -1 and end_idx != -1:
            clean_json = raw_text[start_idx:end_idx+1]
        else:
            clean_json = raw_text
            
        parsed_data = json.loads(clean_json, strict=False)
        
        # 🚀 BỌC THÉP 2: NẾU AI LƯỜI KHÔNG TẠO ĐƯỢC QUIZ THÌ BỎ QUA, KHÔNG SẬP HỆ THỐNG
        valid_quiz = []
        raw_quiz = parsed_data.get("quiz", [])
        if raw_quiz:
            try:
                valid_quiz = extract_json_array(raw_quiz, ["type", "question", "options", "answer"])
            except Exception:
                valid_quiz = [] 

        return {"status": "success", "data": {"report": parsed_data.get("report", "Không thể phân tích báo cáo."), "quiz": valid_quiz}}
    except Exception as e:
        print(f"Lỗi phân tích điểm yếu: {e}")
        return {"status": "error", "message": f"Lỗi AI: {str(e)}"}

# ==================== KHU VỰC FLASHCARDS ====================
@router.post("/api/flashcards")
async def generate_flashcards(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        num_cards = int(data.get("num_cards", 5))
        focus_topic = data.get("focus_topic") # 🚀 2. NHẬN CHỦ ĐỀ TỪ APP

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
        
        if focus_topic:
            # 🚀 NẾU ĐANG HỌC LỘ TRÌNH -> CHỈ BỐC KHÁI NIỆM TRONG BÀI
            search_query = f"Khái niệm và định nghĩa thuộc chủ đề: {focus_topic}"
            context = get_active_context(search_query, user_id, str(notebook_id), k_needed=k_size)
            focus_instruction = f"BÁM SÁT VÀO CHỦ ĐỀ NÀY: {focus_topic}"
        else:
            # 🚀 BÌNH THƯỜNG -> RANDOM CẢ SÁCH
            context = get_random_context(user_id, str(notebook_id), k_needed=k_size)
            focus_areas = [
                "Tập trung vào các thuật ngữ phụ, ít nổi bật",
                "Tìm các con số quan trọng, năm, tỷ lệ phần trăm",
                "Tìm các tên người, tác giả, hoặc công ty được nhắc đến",
                "Khai thác các định nghĩa ngách ở cuối các đoạn văn"
            ]
            focus_instruction = random.choice(focus_areas)
        
        if not context: 
            return {"data": [{"term": "Chưa tải PDF", "definition": "Vui lòng tải tài liệu"}]}
            
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
        if focus_topic:
            deck_title = f"Flashcard Lộ Trình ({datetime.now().strftime('%H:%M')})"

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
# ==================== KHU VỰC ROADMAP (CÓ TIME-GATING) ====================
@router.post("/api/roadmap")
async def generate_roadmap(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = int(data.get("notebook_id", 0))
        
        # 🚀 THUẬT TOÁN 1: KIỂM TRA BỘ NHỚ CỐ ĐỊNH TRƯỚC (CHỐNG RESET)
        res = supabase.table("roadmaps").select("*").eq("notebook_id", notebook_id).eq("user_id", user_id).execute()
        if res.data:
            # Nếu đã có, trả về dữ liệu cũ ngay lập tức kèm tiến độ (current_stage)
            return {
                "status": "success", 
                "current_stage": res.data[0]['current_stage'],
                "data": res.data[0]['roadmap_data']
            }

        # 🚀 NẾU CHƯA CÓ: Kích hoạt AI tạo Lộ trình (Chỉ chạy đúng 1 lần duy nhất trong đời tài liệu này)
        search_query = "Tóm tắt nội dung chính, mục lục, các chương, chủ đề cốt lõi"
        context = get_active_context(search_query, user_id, str(notebook_id), k_needed=15)
        
        prompt = f"""
        Dựa vào TÀI LIỆU sau, tạo Lộ trình học tiêu chuẩn gồm 5 giai đoạn nối tiếp nhau.
        TÀI LIỆU: {context}
        
        ⛔ LUẬT SƯ PHẠM NGHIÊM NGẶT:
        - Sinh viên BẮT BUỘC phải làm Quiz để qua bài. Bạn hãy luôn thêm 1 nhiệm vụ "Làm bài Quiz đánh giá năng lực" vào cuối mỗi giai đoạn.
        
        TRẢ VỀ 1 MẢNG JSON THEO ĐÚNG MẪU NÀY:
        [
          {{
            "day": 1, 
            "title": "Tên chủ đề cơ bản", 
            "estimated_time": "45 phút",
            "tasks": ["Đọc lý thuyết trang X", "Hoàn thành bài Quiz đánh giá năng lực"]
          }}
        ]
        """
        
        raw_text = call_groq(prompt, temp=0.2).replace("```json", "").replace("```", "").strip()
        roadmap_data = extract_json_array(json.loads(raw_text), ["day", "title", "estimated_time", "tasks"]) 
        
        # 🚀 LƯU VĨNH VIỄN VÀO CƠ SỞ DỮ LIỆU
        supabase.table("roadmaps").insert({
            "user_id": user_id,
            "notebook_id": notebook_id,
            "roadmap_data": roadmap_data,
            "current_stage": 1 # Bắt đầu từ ải số 1
        }).execute()
        
        return {"status": "success", "current_stage": 1, "data": roadmap_data}
    except Exception as e:
        print(f"Lỗi hệ thống Roadmap: {e}")
        return {"status": "error", "message": "Không thể tạo lộ trình"}


# ==================== API CỔNG CHẶN 80% (MASTERY GATE) ====================
@router.post("/api/roadmap/submit_gate")
async def check_mastery_gate(request: ScoreRequest):
    try:
        # 1. Lấy thông tin lộ trình hiện tại
        res = supabase.table("roadmaps").select("*").eq("notebook_id", int(request.notebook_id)).eq("user_id", request.user_id).execute()
        if not res.data:
            return {"status": "error", "message": "Chưa có lộ trình."}
            
        current_stage = res.data[0]['current_stage']
        roadmap_length = len(res.data[0]['roadmap_data'])
        
        # 2. THUẬT TOÁN ĐÁNH GIÁ 80%
        accuracy = request.score / request.total
        
        if accuracy >= 0.8: # Đạt từ 80% trở lên
            if current_stage < roadmap_length:
                # VƯỢT ẢI: Nâng cấp current_stage lên +1 và lưu vào DB
                new_stage = current_stage + 1
                supabase.table("roadmaps").update({"current_stage": new_stage}).eq("id", res.data[0]['id']).execute()
                
                msg = f"Tuyệt vời! Bạn đạt {int(accuracy*100)}%, Giai đoạn {new_stage} đã được mở khóa."
                return {"status": "success", "action": "unlocked", "message": msg}
            else:
                return {"status": "success", "action": "completed", "message": "Chúc mừng! Bạn đã tốt nghiệp toàn bộ lộ trình!"}
        else:
            # THẤT BẠI: Giữ nguyên tiến độ, ép học lại
            msg = f"Điểm số của bạn là {int(accuracy*100)}%. Hệ thống yêu cầu 80% để qua bài. Bạn cần ôn tập và làm lại Quiz!"
            return {"status": "success", "action": "blocked", "message": msg}
            
    except Exception as e:
        return {"status": "error", "message": str(e)}
    
# ==================== API TRỌNG TÀI AI CHẤM ĐIỂM TỰ LUẬN ====================
@router.post("/api/quiz/grade_short_answers")
async def grade_short_answers(request: Request):
    try:
        data = await request.json()
        items = data.get("items", []) # Nhận danh sách các câu tự luận từ App gửi lên
        if not items:
            return {"status": "success", "results": []}

        # Định dạng danh sách đề thi để gửi cho AI chấm bài
        formatted_items = ""
        for i, item in enumerate(items):
            formatted_items += f"--- Câu {i+1} ---\nCâu hỏi: {item.get('question')}\nĐáp án chuẩn: {item.get('correct_answer')}\nCâu trả lời của sinh viên: {item.get('user_answer')}\n\n"

        prompt = f"""
        Bạn là một Giám khảo chấm thi đại học nghiêm túc và thông minh. Hãy đánh giá câu trả lời ngắn của sinh viên dựa trên đáp án chuẩn.
        
        ⛔ QUY TẮC CHẤM ĐIỂM TẬP TRUNG VÀO BẢN CHẤT:
        1. Hãy chấm dựa trên Ý NGHĨA và BẢN CHẤT kiến thức. 
        2. Nếu sinh viên trả lời ĐÚNG Ý (dù viết dài hơn, ngắn hơn, dùng từ đồng nghĩa, bổ sung từ đệm như "là", "đó chính là", hoặc có lỗi sai chính tả nhẹ không làm đổi nghĩa câu), bạn phải chấm là true.
        3. Nếu sinh viên trả lời SAI HOÀN TOÀN bản chất, trả lời lạc đề hoặc BỎ TRỐNG không ghi chữ nào, bạn chấm là false.

        DANH SÁCH CÂU HỎI CẦN CHẤM:
        {formatted_items}

        YÊU CẦU TRẢ VỀ: Trả về DUY NHẤT một mảng JSON chứa các giá trị true/false tương ứng theo đúng thứ tự câu hỏi. KHÔNG giải thích dông dài.
        Ví dụ định dạng trả về: [true, false, true]
        """

        # Gọi mô hình nhẹ (llama3-8b) để chấm điểm siêu tốc và tiết kiệm token
        raw_text = call_groq(prompt, is_chat_mode=False, temp=0.1).replace("```json", "").replace("```", "").strip()
        results = json.loads(raw_text)
        
        return {"status": "success", "results": results}
    except Exception as e:
        print(f"🔥 LỖI AI AUTO-GRADER: {e}")
        # Nếu hệ thống lỗi, mặc định cho sai để tránh crash hệ thống
        return {"status": "error", "results": [False * len(items)]}
    

# ==================== THUẬT TOÁN SRS (SUPERMEMO-2) ====================

# 🚀 API 1: TÌM CÁC THẺ FLASHCARD ĐẾN HẠN HÔM NAY
@router.get("/api/flashcards/due/{notebook_id}/{user_id}")
async def get_due_flashcards(notebook_id: int, user_id: str):
    try:
        # Lấy toàn bộ các bộ flashcard của sinh viên
        res = supabase.table("flashcard_decks").select("id, title, cards").eq("notebook_id", notebook_id).eq("user_id", user_id).execute()
        
        due_cards = []
        now = datetime.now()
        
        if res.data:
            for deck in res.data:
                cards = deck.get("cards", [])
                for i, card in enumerate(cards):
                    due_date_str = card.get("due_date")
                    if due_date_str:
                        try:
                            # Xử lý chuỗi thời gian
                            due_date = datetime.fromisoformat(due_date_str.replace('Z', '+00:00')).replace(tzinfo=None)
                            
                            # Nếu ngày hẹn ôn tập NHỎ HƠN HOẶC BẰNG ngày hôm nay -> Cho vào danh sách cần học
                            if due_date <= now:
                                card_info = card.copy()
                                card_info['deck_id'] = deck['id']
                                card_info['card_index'] = i
                                card_info['deck_title'] = deck['title']
                                due_cards.append(card_info)
                        except Exception:
                            continue
                            
        return {"status": "success", "data": due_cards, "total_due": len(due_cards)}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# 🚀 API 2: CẬP NHẬT CHỈ SỐ NÃO BỘ SAU KHI HỌC
@router.put("/api/flashcards/update_card")
async def update_single_card(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id")
        deck_id = data.get("deck_id")
        card_index = data.get("card_index")
        updated_meta = data.get("card_data") # Chứa {ease, interval, due_date, reps} từ Flutter gửi lên
        
        # Lấy mảng cards gốc
        res = supabase.table("flashcard_decks").select("cards").eq("id", deck_id).eq("user_id", user_id).execute()
        if not res.data: 
            return {"status": "error", "message": "Không tìm thấy bộ thẻ"}
            
        cards = res.data[0]['cards']
        
        # Ghi đè chỉ số trí nhớ mới vào thẻ
        if 0 <= card_index < len(cards):
            cards[card_index].update(updated_meta)
            # Đồng bộ lại lên Cloud
            supabase.table("flashcard_decks").update({"cards": cards}).eq("id", deck_id).eq("user_id", user_id).execute()
            return {"status": "success", "message": "Đã lưu trí nhớ"}
        else:
            return {"status": "error", "message": "Lỗi vị trí thẻ"}
            
    except Exception as e:
        return {"status": "error", "message": str(e)}
    
# 🚀 API ĐẾM SỐ LƯỢNG THẺ ĐẾN HẠN (DÙNG CHO THÔNG BÁO MÀN HÌNH CHÍNH)
@router.get("/api/flashcards/due_count/{notebook_id}/{user_id}")
async def get_due_flashcards_count(notebook_id: int, user_id: str):
    try:
        # Lấy tất cả bộ thẻ của user trong notebook này
        res = supabase.table("flashcard_decks").select("cards").eq("notebook_id", notebook_id).eq("user_id", user_id).execute()
        
        total_due = 0
        now = datetime.now()
        
        if res.data:
            for deck in res.data:
                for card in deck.get("cards", []):
                    due_date_str = card.get("due_date")
                    if due_date_str:
                        try:
                            # Phân tích chuỗi thời gian an toàn
                            due_date = datetime.fromisoformat(due_date_str.replace('Z', '+00:00')).replace(tzinfo=None)
                            if due_date <= now:
                                total_due += 1
                        except Exception:
                            pass
                    else:
                        total_due += 1 # Nếu thẻ bị lỗi mất ngày, mặc định là cần học
                        
        return {"status": "success", "total_due": total_due}
    except Exception as e:
        return {"status": "error", "message": str(e)}
    
@router.post("/api/concept_map")
async def generate_concept_map(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id")
        notebook_id = data.get("notebook_id")
        
        # Lấy tài liệu 
        search_query = "Tóm tắt các định nghĩa, khái niệm cốt lõi, thành phần chính và mối liên hệ giữa chúng."
        context_text = get_active_context(search_query, user_id, notebook_id, k_needed=15)
        
        if not context_text:
            return {"status": "error", "message": "Chưa có tài liệu để phân tích."}
            
        prompt = f"""
        Bạn là chuyên gia thiết kế Sơ đồ tư duy (Mind Map).
        Dựa vào TÀI LIỆU sau, hãy trích xuất các khái niệm chính và phân cấp chúng.
        TÀI LIỆU: {context_text}
        
        ⛔ YÊU CẦU NGHIÊM NGẶT:
        1. Tạo 1 "Khái niệm trung tâm" và chia ra các "Khái niệm nhánh". Tối đa 15 nodes.
        2. CHỈ trả về JSON thuần túy, tuyệt đối KHÔNG có dấu markdown (```json), KHÔNG giải thích.
        
        MẪU JSON CHUẨN:
        {{
            "nodes": [
                {{"id": "1", "label": "Chủ nghĩa tư bản"}},
                {{"id": "2", "label": "Tổ chức độc quyền"}},
                {{"id": "3", "label": "Xuất khẩu tư bản"}}
            ],
            "edges": [
                {{"from": "1", "to": "2"}},
                {{"from": "1", "to": "3"}}
            ]
        }}
        """
        
        # Gọi thẳng Groq API (Chỗ này lúc nãy bạn gõ nhầm chữ h0 nè)
        client = Groq(api_key=GROQ_API_KEYS[0])
        chat_completion = client.chat.completions.create(
            messages=[{"role": "user", "content": prompt}],
            model="llama-3.3-70b-versatile",
            temperature=0.1
        )
        
        raw_response = chat_completion.choices[0].message.content
        
        # Làm sạch chuỗi đề phòng AI lỡ sinh ra markdown
        clean_json = raw_response.replace("```json", "").replace("```", "").strip()
        map_data = json.loads(clean_json)
        
        return {"status": "success", "data": map_data}
    except Exception as e:
        print(f"Lỗi Concept Map: {e}")
        return {"status": "error", "message": str(e)}