from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
import io
import edge_tts
import json
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
        
        context_text, references_list = get_active_context(request.message, request.user_id, request.notebook_id, k_needed=12, return_refs=True)
        
        # 🛡️ KIỂM TRA MÀNG LỌC: Nếu hàm core.py trả về rỗng do lạc đề, chặn luôn từ cửa
        if not context_text:
            async def quick_reply(): yield "Rất tiếc, thông tin này không có trong tài liệu bạn đã tải lên dự án này. Vui lòng hỏi các nội dung xoay quanh tài liệu nhé! 📚"
            # Lưu câu trả lời từ chối vào database luôn
            supabase.table("chat_history").insert({"user_id": request.user_id, "notebook_id": int(request.notebook_id), "sender": "ai", "message": "Rất tiếc, thông tin này không có trong tài liệu bạn đã tải lên dự án này. Vui lòng hỏi các nội dung xoay quanh tài liệu nhé! 📚"}).execute()
            return StreamingResponse(quick_reply(), media_type="text/plain")
            
        prompt = f"""
        TÀI LIỆU HỌC TẬP THUỘC VỀ USER {request.user_id}: 
        {context_text}
        
        CÂU HỎI CỦA HỌC SINH: {request.message}
        
        ⛔ LƯU Ý SỐNG CÒN VÀ KỶ LUẬT:
        1. NẾU MỤC TÀI LIỆU KHÔNG CÓ THÔNG TIN LIÊN QUAN, BẠN BẮT BUỘC PHẢI TRẢ LỜI ĐÚNG CÂU NÀY: "Rất tiếc, thông tin này không có trong tài liệu bạn đã tải lên dự án này."
        2. TUYỆT ĐỐI KHÔNG ĐƯỢC dùng kiến thức bên ngoài (ngoài tài liệu) để trả lời, kể cả khi bạn biết đáp án. Không bịa đặt, không suy diễn vượt quá nội dung tài liệu.
        
        ✅ YÊU CẦU TRÌNH BÀY:
        1. Chỉ trả lời dựa 100% vào TÀI LIỆU.
        2. Trích dẫn nguồn bằng cách thêm ngoặc vuông chứa số của nguồn vào cuối câu. Ví dụ: "Theo định nghĩa [1]... và ứng dụng [2]."
        3. Tuyệt đối không tự tạo link URL hay định dạng Markdown phức tạp. Chỉ dùng [1], [2], v.v.
        """
        async def generate_chat():
            full_ai_response = ""
            try:
                chat_completion = groq_client.chat.completions.create(
                    messages=[{"role": "system", "content": "Bạn là Giáo sư AI..."}, {"role": "user", "content": prompt}],
                    model=GROQ_MODEL, temperature=0.1, max_tokens=3000, stream=True
                )
                for chunk in chat_completion:
                    if chunk.choices[0].delta.content:
                        text_chunk = chunk.choices[0].delta.content
                        full_ai_response += text_chunk
                        yield text_chunk
                
                # 🚀 ĐÃ NÂNG CẤP: Bắn mảng JSON Source Map xuống dưới đuôi Stream qua ký tự phân tách
                if full_ai_response and references_list:
                    # Ký tự phân tách giúp Frontend biết đâu là chữ, đâu là Map dữ liệu
                    metadata_marker = f"|||METADATA|||{json.dumps(references_list)}"
                    yield metadata_marker
                    full_ai_response += metadata_marker

                if full_ai_response:
                    supabase.table("chat_history").insert({"user_id": request.user_id, "notebook_id": int(request.notebook_id), "sender": "ai", "message": full_ai_response}).execute()
                    
            except Exception as e: yield f"\n[Lỗi kết nối AI: {str(e)}]"
            
        return StreamingResponse(generate_chat(), media_type="text/plain")
    except Exception as e:
        async def error_reply(): yield f"Hệ thống báo lỗi: {str(e)}"
        return StreamingResponse(error_reply(), media_type="text/plain")