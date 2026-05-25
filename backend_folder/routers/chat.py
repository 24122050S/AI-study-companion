from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
import io
import edge_tts
import os
from models import ChatRequest
from core import supabase, get_active_context, VECTOR_DB_ROOT, groq_client, GROQ_MODEL

router = APIRouter()

@router.get("/api/tts")
async def text_to_speech(text: str):
    try:
        communicate = edge_tts.Communicate(text, "vi-VN-HoaiMyNeural", rate="+5%") 
        audio_data = b""
        async for chunk in communicate.stream():
            if chunk["type"] == "audio": audio_data += chunk["data"]
        return StreamingResponse(io.BytesIO(audio_data), media_type="audio/mpeg")
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@router.get("/api/chat_history/{user_id}/{notebook_id}")
async def get_chat_history(user_id: str, notebook_id: int):
    try:
        res = supabase.table("chat_history").select("*").eq("user_id", user_id).eq("notebook_id", notebook_id).order("created_at", desc=False).execute()
        return {"status": "success", "data": res.data}
    except Exception as e: return {"status": "error", "message": str(e)}

@router.post("/api/chat")
async def chat_with_ai(request: ChatRequest):
    try:
        supabase.table("chat_history").insert({"user_id": request.user_id, "notebook_id": int(request.notebook_id), "sender": "user", "message": request.message}).execute()
        
        # 👈 LẤY CẢ BỘ TEXT VÀ BỘ LINK TỪ CORE
        context_text, references_list = get_active_context(request.message, request.user_id, request.notebook_id, k_needed=12, return_refs=True)
        
        if not context_text and not os.path.exists(os.path.join(VECTOR_DB_ROOT, request.user_id, request.notebook_id)):
            async def quick_reply(): yield "Vui lòng tải tài liệu PDF lên trước nhé! 📚"
            return StreamingResponse(quick_reply(), media_type="text/plain")
            
        prompt = f"""
        TÀI LIỆU HỌC TẬP THUỘC VỀ USER {request.user_id}: 
        {context_text}
        
        CÂU HỎI CỦA HỌC SINH: {request.message}
        
        ⛔ LƯU Ý SỐNG CÒN:
        - Đánh giá xem CÂU HỎI có nằm trong TÀI LIỆU không. Nếu KHÔNG, BẮT BUỘC TỪ CHỐI.
        
        ✅ YÊU CẦU:
        1. BẮT BUỘC DỰA 100% VÀO TÀI LIỆU.
        2. Trích dẫn nguồn bằng cách thêm ngoặc vuông chứa số của nguồn vào cuối câu. Ví dụ: "Theo định nghĩa [1]... và ứng dụng [2]."
        3. TUYỆT ĐỐI KHÔNG tự tạo link URL hay định dạng Markdown phức tạp. CHỈ DÙNG [1], [2], v.v.
        """
        async def generate_chat():
            full_ai_response = ""
            try:
                chat_completion = groq_client.chat.completions.create(
                    messages=[{"role": "system", "content": "Bạn là Giáo sư AI..."}, {"role": "user", "content": prompt}],
                    model=GROQ_MODEL, temperature=0.4, max_tokens=3000, stream=True
                )
                for chunk in chat_completion:
                    if chunk.choices[0].delta.content:
                        text_chunk = chunk.choices[0].delta.content
                        full_ai_response += text_chunk
                        yield text_chunk
                
                # 🔥 BACKEND TỰ ĐỘNG GẮN LINK TRÍCH DẪN CHUẨN XÁC VÀO CUỐI CÙNG
                if full_ai_response and references_list:
                    footer = "\n\n---\n**🔍 Nguồn tham khảo:**\n"
                    yield footer
                    full_ai_response += footer
                    
                    # Loại bỏ các nguồn trùng lặp
                    unique_refs = list(dict.fromkeys(references_list))
                    for ref in unique_refs:
                        yield ref + "\n"
                        full_ai_response += ref + "\n"

                # Lưu vào DB chuỗi hoàn chỉnh (đã có footer)
                if full_ai_response:
                    supabase.table("chat_history").insert({"user_id": request.user_id, "notebook_id": int(request.notebook_id), "sender": "ai", "message": full_ai_response}).execute()
                    
            except Exception as e: yield f"\n[Lỗi kết nối AI: {str(e)}]"
            
        return StreamingResponse(generate_chat(), media_type="text/plain")
    except Exception as e:
        async def error_reply(): yield f"Hệ thống báo lỗi: {str(e)}"
        return StreamingResponse(error_reply(), media_type="text/plain")