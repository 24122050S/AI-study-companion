from fastapi import APIRouter
from datetime import datetime, timedelta
from models import ScoreRequest, NoteRequest, NotebookRequest
from core import supabase, call_groq
from fastapi import Request

router = APIRouter()

@router.post("/api/notebooks")
async def create_notebook(request: NotebookRequest):
    res = supabase.table("notebooks").insert({"user_id": request.user_id, "title": request.title}).execute()
    return {"status": "success", "data": res.data[0]}

@router.get("/api/notebooks/{user_id}")
async def get_notebooks(user_id: str):
    return supabase.table("notebooks").select("*").eq("user_id", user_id).order("created_at", desc=True).execute().data

@router.put("/api/notebooks/{notebook_id}")
async def rename_notebook(notebook_id: int, request: Request):
    try:
        data = await request.json()
        new_title = data.get("title")
        if not new_title:
            return {"status": "error", "message": "Tên không được để trống"}
            
        supabase.table("notebooks").update({"title": new_title}).eq("id", notebook_id).execute()
        return {"status": "success", "message": "Đã đổi tên thành công!"}
    except Exception as e:
        return {"status": "error", "message": f"Lỗi hệ thống: {str(e)}"}

@router.delete("/api/notebooks/{notebook_id}")
async def delete_notebook(notebook_id: int):
    try:
        supabase.table("chat_history").delete().eq("notebook_id", notebook_id).execute()
        supabase.table("uploaded_files").delete().eq("notebook_id", notebook_id).execute()
        supabase.table("notes").delete().eq("notebook_id", notebook_id).execute()
        supabase.table("quiz_decks").delete().eq("notebook_id", notebook_id).execute()
        supabase.table("flashcard_decks").delete().eq("notebook_id", notebook_id).execute()
        supabase.table("documents").delete().eq("metadata->>notebook_id", str(notebook_id)).execute()
        supabase.table("notebooks").delete().eq("id", notebook_id).execute()
        return {"status": "success", "message": "Đã dọn sạch và xóa dự án thành công!"}
    except Exception as e:
        return {"status": "error", "message": f"Không thể xóa dự án: {str(e)}"}

@router.post("/api/score")
async def save_score(request: ScoreRequest):
    supabase.table("history").insert({
        "user_id": request.user_id,
        "topic": request.topic,
        "score": request.score,
        "total": request.total,
        "percentage": int((request.score / request.total) * 100)
    }).execute()
    return {"status": "success"}

@router.get("/api/dashboard/{user_id}")
async def get_dashboard(user_id: str):
    res = supabase.table("history").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
    if not res.data: return {"status": "success", "streak": 0, "notifications": []}
    
    streak = 1
    today = datetime.now().date()
    prev_date = today
    for r in res.data:
        r_date = datetime.strptime(r['created_at'].split("T")[0], "%Y-%m-%d").date()
        if r_date == prev_date: continue
        if r_date == prev_date - timedelta(days=1):
            streak += 1
            prev_date = r_date
        else: break
        
    notifications = []
    for r in res.data[:3]:
        pct = r['percentage']
        t = "success" if pct >= 80 else "warning" if pct >= 50 else "danger"
        msg = f"Bạn đã hoàn thành bài Quiz '{r['topic']}' xuất sắc với {pct}%!" if pct >= 80 else f"Kết quả bài Quiz '{r['topic']}' đạt {pct}%. Hãy cố gắng hơn nhé!"
        notifications.append({"type": t, "message": msg, "time": r['created_at'].split("T")[0]})
        
    return {"status": "success", "streak": streak, "notifications": notifications}

@router.get("/api/recommend/{user_id}")
async def get_recommendation(user_id: str):
    # 1. Kéo lịch sử 10 bài làm gần nhất kèm theo Tên chủ đề (Topic)
    res = supabase.table("history").select("topic, percentage, created_at").eq("user_id", user_id).order("created_at", desc=True).limit(10).execute()
    
    if not res.data: 
        return {"recommendation": "Chào mừng bạn! Hãy làm bài Quiz đầu tiên để AI có thể phân tích và định hướng lộ trình học nhé."}
    
    # 2. Tổng hợp dữ liệu thành mảng văn bản cho AI dễ đọc
    history_summary = []
    for r in res.data:
        history_summary.append(f"- Chủ đề '{r['topic']}': Đạt {r['percentage']}%")
        
    history_text = "\n".join(history_summary)
    
    # 3. Kịch bản Prompt Ép AI trở thành Gia sư Chiến lược
    prompt = f"""
    Bạn là một Gia sư AI chuyên tư vấn chiến lược học tập.
    Dưới đây là lịch sử điểm số 10 bài kiểm tra gần nhất của học sinh:
    
    {history_text}
    
    Dựa vào dữ liệu trên, hãy đưa ra một GỢI Ý ĐỊNH HƯỚNG CÁ NHÂN HÓA theo cấu trúc block rõ ràng:
    
    1. **Đánh giá phong độ:** (1 câu ngắn gọn nhìn nhận tổng quan tiến độ).
    2. **Ưu tiên học trước:** (Chỉ đích danh các CHỦ ĐỀ có điểm số thấp dưới 80%. Khuyên học sinh ôn lại lý thuyết phần này).
    3. **Cần luyện tập thêm:** (Chỉ đích danh các CHỦ ĐỀ có điểm ở mức khá 80-90% cần làm thêm bài tập để tối ưu thời gian).
    
    ⛔ YÊU CẦU NGHIÊM NGẶT:
    - Viết ngắn gọn, súc tích, truyền động lực. (Tối đa 150 chữ).
    - KHÔNG tự bịa ra các chủ đề không có trong lịch sử.
    """
    
    try: 
        # Gọi mô hình mạnh để phân tích logic tốt hơn
        ai_advice = call_groq(prompt, temp=0.3)
        return {"recommendation": ai_advice.strip()}
    except Exception as e: 
        print(f"Lỗi Recommendation: {e}")
        return {"recommendation": "Hệ thống AI đang tổng hợp dữ liệu. Bạn hãy quay lại sau ít phút nhé!"}

@router.post("/api/notes")
async def add_note(request: NoteRequest):
    supabase.table("notes").insert({"user_id": request.user_id, "notebook_id": int(request.notebook_id), "title": request.title, "content": request.content}).execute()
    return {"status": "success"}

@router.get("/api/notes/{user_id}/{notebook_id}")
async def get_notes(user_id: str, notebook_id: int):
    res = supabase.table("notes").select("*").eq("user_id", user_id).eq("notebook_id", notebook_id).order("created_at", desc=True).execute()
    return res.data

@router.delete("/api/notes/{note_id}")
async def delete_note(note_id: int):
    try:
        supabase.table("notes").delete().eq("id", note_id).execute()
        return {"status": "success", "message": "Đã xóa ghi chú"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@router.put("/api/notes/{note_id}")
async def update_note(note_id: int, request: Request):
    try:
        data = await request.json()
        title = data.get("title", "Ghi chú")
        content = data.get("content", "")
        supabase.table("notes").update({"title": title, "content": content}).eq("id", note_id).execute()
        return {"status": "success", "message": "Đã cập nhật ghi chú"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# ==================== KHU VỰC THÔNG BÁO (INBOX PATTERN & TIME-BOMB) ====================
@router.get("/api/notifications/{user_id}/{notebook_id}")
async def get_notifications(user_id: str, notebook_id: int):
    try:
        notifications = []
        unread_count = 0
        now = datetime.now()
        
        flashcard_res = supabase.table("flashcard_decks").select("cards").eq("notebook_id", notebook_id).eq("user_id", user_id).execute()
        total_due = 0
        if flashcard_res.data:
            for deck in flashcard_res.data:
                for card in deck.get("cards", []):
                    due_date_str = card.get("due_date")
                    if due_date_str:
                        try:
                            due_date = datetime.fromisoformat(due_date_str.replace('Z', '+00:00')).replace(tzinfo=None)
                            if due_date <= now: total_due += 1
                        except: pass
                    else: total_due += 1
                    
        if total_due > 0:
            notifications.append({
                "id": 0, 
                "type": "warning", 
                "title": "Nhiệm vụ Flashcard",
                "message": f"Có {total_due} thẻ Flashcard đang đến hạn. Hãy ôn tập ngay để duy trì trí nhớ nhé!", 
                "time": "Vừa xong",
                "is_read": False
            })
            unread_count += 1

        now_str = now.isoformat()
        res = supabase.table("notifications")\
            .select("*")\
            .eq("user_id", user_id)\
            .eq("notebook_id", notebook_id)\
            .lte("created_at", now_str)\
            .order("created_at", desc=True)\
            .limit(20)\
            .execute()
        
        if res.data:
            for n in res.data:
                notifications.append({
                    "id": n['id'],
                    "type": n['type'],
                    "title": n['title'],
                    "message": n['message'],
                    "time": n['created_at'].split("T")[0] + " " + n['created_at'].split("T")[1][:5],
                    "is_read": n['is_read']
                })
                if not n['is_read']: unread_count += 1
                    
        return {"status": "success", "unread_count": unread_count, "notifications": notifications}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@router.put("/api/notifications/read_all/{user_id}/{notebook_id}")
async def mark_all_notifications_read(user_id: str, notebook_id: int):
    try:
        now_str = datetime.now().isoformat()
        supabase.table("notifications").update({"is_read": True}).eq("user_id", user_id).eq("notebook_id", notebook_id).eq("is_read", False).lte("created_at", now_str).execute()
        return {"status": "success"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@router.post("/api/notifications")
async def create_notification(request: Request):
    try:
        data = await request.json()
        delay_hours = float(data.get("delay_hours", 0))
        trigger_time = datetime.now() + timedelta(hours=delay_hours)
        
        supabase.table("notifications").insert({
            "user_id": data.get("user_id"),
            "notebook_id": data.get("notebook_id"),
            "title": data.get("title", "Thông báo mới"),
            "message": data.get("message"),
            "type": data.get("type", "info"),
            "is_read": False,
            "created_at": trigger_time.isoformat() 
        }).execute()
        return {"status": "success"}
    except Exception as e:
        return {"status": "error", "message": str(e)}