# ============================================================
#  FILE MỚI: GIẢI THÍCH KHÁI NIỆM TRÊN SƠ ĐỒ TƯ DUY (RAG)
#  📂 Vị trí đặt file: backend_folder/routers/concept_explain.py
#  Endpoint: POST /api/concept_map/explain
# ============================================================
from fastapi import APIRouter, Request
from core import get_active_context, call_groq

router = APIRouter()


@router.post("/api/concept_map/explain")
async def explain_concept_node(request: Request):
    try:
        data = await request.json()
        user_id = data.get("user_id", "")
        notebook_id = data.get("notebook_id", "")
        concept = (data.get("concept") or "").strip()

        if not concept:
            return {"status": "error", "message": "Thiếu tên khái niệm cần giải thích."}

        # 1. RAG: Embed tên khái niệm -> tìm 8 đoạn tài liệu liên quan nhất trên Supabase Vector
        search_query = f"Định nghĩa, giải thích, đặc điểm và ví dụ về khái niệm: {concept}"
        context_text = get_active_context(search_query, user_id, str(notebook_id), k_needed=8)

        if not context_text:
            return {"status": "error", "message": "Không tìm thấy nội dung liên quan trong tài liệu của bạn."}

        # 2. Đưa ngữ cảnh RAG vào prompt để AI giải thích bám sát tài liệu
        prompt = f"""
        Dựa 100% vào TÀI LIỆU dưới đây, hãy giải thích khái niệm: "{concept}".

        TÀI LIỆU:
        {context_text}

        ⛔ YÊU CẦU NGHIÊM NGẶT:
        1. Giải thích ngắn gọn, dễ hiểu cho sinh viên (khoảng 100-150 từ).
        2. Trình bày theo mạch: Định nghĩa -> Ý chính / đặc điểm -> Ví dụ (nếu tài liệu có).
        3. CHỈ dùng thông tin trong TÀI LIỆU. Nếu tài liệu không nói rõ về "{concept}",
           hãy trả lời đúng câu: "Tài liệu chưa có thông tin chi tiết về khái niệm này."
        4. Trả lời bằng tiếng Việt, văn xuôi tự nhiên, KHÔNG dùng markdown (không **, không #).
        """

        explanation = call_groq(prompt, is_chat_mode=True, temp=0.3)

        return {"status": "success", "data": {"concept": concept, "explanation": explanation.strip()}}
    except Exception as e:
        print(f"Lỗi giải thích node: {e}")
        return {"status": "error", "message": str(e)}
