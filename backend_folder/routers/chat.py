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
        
        # Cảm biến ý định người dùng
        user_msg_lower = request.message.lower()
        is_summarizing = any(kw in user_msg_lower for kw in ["tóm tắt", "tổng hợp", "tổng quan", "khái quát", "toàn bộ"])
        
        # Mở rộng vùng quét nếu yêu cầu tóm tắt (từ 12 lên 40 chunks để đọc siêu sâu)
        chunk_size = 40 if is_summarizing else 12
        
        # Kiểm tra xem có đang bật chế độ học theo Roadmap không
        if getattr(request, "focus_topic", None):
            search_query = f"Nội dung trọng tâm: {request.focus_topic}. {request.message}"

        context_text, references_list = get_active_context(search_query, request.user_id, str(request.notebook_id), k_needed=chunk_size, return_refs=True)
        
        if not context_text:
            async def quick_reply(): yield "Rất tiếc, thông tin này không có trong tài liệu bạn đã tải lên dự án này. Vui lòng hỏi các nội dung xoay quanh tài liệu nhé! 📚"
            supabase.table("chat_history").insert({"user_id": request.user_id, "notebook_id": int(request.notebook_id), "sender": "ai", "message": "Rất tiếc, thông tin này không có trong tài liệu bạn đã tải lên dự án này."}).execute()
            return StreamingResponse(quick_reply(), media_type="text/plain")

        # ==========================================
        # 🚀 BƯỚC 4.2: DẶN DÒ AI VÀO "KỶ LUẬT" (ĐÃ GỘP TẤT CẢ YÊU CẦU)
        # ==========================================
        system_instruction = "Bạn là Giáo sư AI thông minh và tận tâm."
        
        # YÊU CẦU 1: Ép kỷ luật Lộ trình & Số trang
        if getattr(request, "focus_topic", None):
            system_instruction += f" HIỆN TẠI SINH VIÊN ĐANG HỌC THEO LỘ TRÌNH: '{request.focus_topic}'. LỆNH BẮT BUỘC: Bạn CHỈ ĐƯỢC PHÉP đọc và sử dụng dữ liệu nằm đúng trong GIỚI HẠN SỐ TRANG được chỉ định. NẾU thông tin ở trang khác, BẠN PHẢI BỎ QUA HOÀN TOÀN."
            
        # YÊU CẦU 2: Quy tắc Tóm tắt siêu chi tiết & Markdown của bạn
        if is_summarizing:
            system_instruction += """ BẠN ĐANG ĐƯỢC YÊU CẦU TÓM TẮT TÀI LIỆU. Hãy tuân thủ NGHIÊM NGẶT các quy tắc sau:
            1. BẮT BUỘC TÓM TẮT THEO CẤU TRÚC CHƯƠNG/MỤC (Dựa trên các phần có trong tài liệu). TUYỆT ĐỐI không tóm tắt lố qua số trang quy định nếu có giới hạn.
            2. Mỗi mục lớn phải có Tiêu đề rõ ràng (Sử dụng Markdown Heading như ## Chương 1:..., ## Mục 1:...).
            3. Dưới mỗi Tiêu đề, phải phân tích CỰC KỲ CHI TIẾT các khái niệm, định nghĩa và ý chính. Tuyệt đối KHÔNG viết ngắn.
            4. Sử dụng gạch đầu dòng (Bullet points) và In đậm (**text**) để làm nổi bật từ khóa quan trọng.
            """
            
        prompt = f"""
        TÀI LIỆU HỌC TẬP (Thuộc về user {request.user_id}, mỗi đoạn đều có ghi chú số trang ở đầu): 
        {context_text}
        
        YÊU CẦU CỦA HỌC SINH: {request.message}
        
        ⛔ LƯU Ý SỐNG CÒN VÀ KỶ LUẬT:
        1. KIỂM SOÁT PHẠM VI TRANG: Nếu học sinh đang học theo Lộ trình bị giới hạn phạm vi trang, BẠN CHỈ ĐƯỢC LẤY THÔNG TIN TỪ CÁC TRANG TRONG GIỚI HẠN ĐÓ. Nhắm mắt phớt lờ mọi thông tin từ các trang khác.
        2. CÂU TRẢ LỜI BẮT BUỘC (YÊU CẦU CŨ): NẾU MỤC TÀI LIỆU KHÔNG CÓ THÔNG TIN LIÊN QUAN HOẶC NẰM NGOÀI PHẠM VI TRANG CHO PHÉP, BẠN BẮT BUỘC PHẢI TRẢ LỜI ĐÚNG CÂU NÀY: "Rất tiếc, thông tin này không có trong tài liệu bạn đã tải lên dự án này."
        3. TUYỆT ĐỐI KHÔNG ĐƯỢC dùng kiến thức bên ngoài (ngoài tài liệu) để trả lời.
        
        ✅ YÊU CẦU TRÌNH BÀY:
        1. Chỉ trả lời dựa 100% vào TÀI LIỆU.
        2. Trích dẫn nguồn bằng cách thêm ngoặc vuông chứa số của nguồn vào cuối câu. Ví dụ: "Theo định nghĩa [1]... và ứng dụng [2]."
        """
        
        async def generate_chat():
            full_ai_response = ""
            success = False
            last_error = ""
            
            models_to_try = ["llama-3.3-70b-versatile", "llama3-8b-8192", "mixtral-8x7b-32768"]
            keys_to_try = list(GROQ_API_KEYS)
            random.shuffle(keys_to_try)
            
            for model in models_to_try:
                if success: break
                for key in keys_to_try:
                    try:
                        client = Groq(api_key=key)
                        chat_completion = client.chat.completions.create(
                            messages=[{"role": "system", "content": system_instruction}, {"role": "user", "content": prompt}],
                            model=model, temperature=0.1, max_tokens=4000, stream=True
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