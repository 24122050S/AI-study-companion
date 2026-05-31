from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
import io
import edge_tts
import os
import json
import random
from groq import Groq
from models import ChatRequest
# 🚀 Import GROQ_API_KEYS từ core để Chat cũng có thể xoay tua
from core import supabase, get_active_context, GROQ_API_KEYS

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
        
        # ==========================================
        # 🚀 BƯỚC 4.1: ÉP KHU VỰC TÌM KIẾM TÀI LIỆU
        # ==========================================
        search_query = request.message
        # Kiểm tra xem có đang bật chế độ học theo Roadmap không (focus_topic)
        if getattr(request, "focus_topic", None):
            search_query = f"Nội dung trọng tâm thuộc chủ đề: {request.focus_topic}. {request.message}"

        context_text, references_list = get_active_context(search_query, request.user_id, request.notebook_id, k_needed=12, return_refs=True)
        
        if not context_text:
            async def quick_reply(): yield "Rất tiếc, thông tin này không có trong tài liệu bạn đã tải lên dự án này. Vui lòng hỏi các nội dung xoay quanh tài liệu nhé! 📚"
            supabase.table("chat_history").insert({"user_id": request.user_id, "notebook_id": int(request.notebook_id), "sender": "ai", "message": "Rất tiếc, thông tin này không có trong tài liệu bạn đã tải lên dự án này. Vui lòng hỏi các nội dung xoay quanh tài liệu nhé! 📚"}).execute()
            return StreamingResponse(quick_reply(), media_type="text/plain")

        # ==========================================
        # 🚀 BƯỚC 4.2: DẶN DÒ AI VÀO "KỶ LUẬT" LỘ TRÌNH
        # ==========================================
        system_instruction = "Bạn là Giáo sư AI thông minh và tận tâm."
        if getattr(request, "focus_topic", None):
            system_instruction += f" HIỆN TẠI SINH VIÊN ĐANG HỌC GIAI ĐOẠN: '{request.focus_topic}'. TUYỆT ĐỐI CHỈ trả lời và hướng dẫn các kiến thức xoay quanh phần này, KHÔNG ĐƯỢC lan man sang chủ đề khác."
            
        prompt = f"""
        TÀI LIỆU HỌC TẬP THUỘC VỀ USER {request.user_id}: 
        {context_text}
        
        CÂU HỎI CỦA HỌC SINH: {request.message}
        
        ⛔ LƯU Ý SỐNG CÒN VÀ KỶ LUẬT:
        1. NẾU MỤC TÀI LIỆU KHÔNG CÓ THÔNG TIN LIÊN QUAN, BẠN BẮT BUỘC PHẢI TRẢ LỜI ĐÚNG CÂU NÀY: "Rất tiếc, thông tin này không có trong tài liệu bạn đã tải lên dự án này."
        2. TUYỆT ĐỐI KHÔNG ĐƯỢC dùng kiến thức bên ngoài (ngoài tài liệu) để trả lời.
        
        ✅ YÊU CẦU TRÌNH BÀY:
        1. Chỉ trả lời dựa 100% vào TÀI LIỆU.
        2. Trích dẫn nguồn bằng cách thêm ngoặc vuông chứa số của nguồn vào cuối câu. Ví dụ: "Theo định nghĩa [1]... và ứng dụng [2]."
        """
        
        async def generate_chat():
            full_ai_response = ""
            success = False
            last_error = ""
            
            # Chiến thuật xoay tua Key và Model
            models_to_try = ["llama-3.3-70b-versatile", "llama3-8b-8192", "mixtral-8x7b-32768"]
            keys_to_try = list(GROQ_API_KEYS)
            random.shuffle(keys_to_try)
            
            for model in models_to_try:
                if success: break
                for key in keys_to_try:
                    try:
                        client = Groq(api_key=key)
                        chat_completion = client.chat.completions.create(
                            # 🚀 BƯỚC 4.3: TRUYỀN LỆNH KỶ LUẬT VÀO ĐÂY
                            messages=[{"role": "system", "content": system_instruction}, {"role": "user", "content": prompt}],
                            model=model, temperature=0.1, max_tokens=3000, stream=True
                        )
                        for chunk in chat_completion:
                            if chunk.choices[0].delta.content:
                                text_chunk = chunk.choices[0].delta.content
                                full_ai_response += text_chunk
                                yield text_chunk
                                
                        success = True
                        break 
                    except Exception as e:
                        last_error = str(e)
                        continue 
                        
            if not success:
                yield f"\n[Hệ thống đang quá tải Token. Đã tự động thử {len(keys_to_try)} API Key và {len(models_to_try)} Mô hình nhưng đều thất bại. Chi tiết: {last_error}]"
                return

            if full_ai_response and references_list:
                filtered_refs = [ref for ref in references_list if f"[{ref['id']}]" in full_ai_response]
                final_refs = filtered_refs if filtered_refs else references_list
                
                metadata_marker = f"|||METADATA|||{json.dumps(final_refs)}"
                yield metadata_marker
                full_ai_response += metadata_marker

            if full_ai_response:
                supabase.table("chat_history").insert({"user_id": request.user_id, "notebook_id": int(request.notebook_id), "sender": "ai", "message": full_ai_response}).execute()
                
        return StreamingResponse(generate_chat(), media_type="text/plain")
    except Exception as e:
        async def error_reply(): yield f"Hệ thống báo lỗi: {str(e)}"
        return StreamingResponse(error_reply(), media_type="text/plain")