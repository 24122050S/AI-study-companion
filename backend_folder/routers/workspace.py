from fastapi import APIRouter
from datetime import datetime, timedelta
from models import ScoreRequest, NoteRequest, NotebookRequest
from core import supabase, call_groq
import os
import shutil
from core import VECTOR_DB_ROOT
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
            
        # Cập nhật tên mới vào Supabase
        supabase.table("notebooks").update({"title": new_title}).eq("id", notebook_id).execute()
        return {"status": "success", "message": "Đã đổi tên thành công!"}
    except Exception as e:
        return {"status": "error", "message": f"Lỗi hệ thống: {str(e)}"}

# 🛠️ ĐÃ CHỈNH SỬA: Thêm message phản hồi rõ ràng để Flutter xử lý hiển thị SnackBar tốt hơn
@router.delete("/api/notebooks/{notebook_id}")
async def delete_notebook(notebook_id: int):
    try:
        # 1. Tìm user_id của notebook để định vị chính xác folder chứa dữ liệu Vector
        res = supabase.table("notebooks").select("user_id").eq("id", notebook_id).execute()
        if res.data:
            user_id = res.data[0]['user_id']
            path = os.path.join(VECTOR_DB_ROOT, user_id, str(notebook_id))
            # 2. Xóa sạch folder vector lưu cục bộ trên máy tính
            if os.path.exists(path): 
                shutil.rmtree(path)
                
        # 3. Tiến hành xóa notebook trong database Supabase
        # (Lưu ý: Đảm bảo các bảng liên quan như quiz_decks, flashcard_decks đã được set "ON DELETE CASCADE" trong SQL)
        supabase.table("notebooks").delete().eq("id", notebook_id).execute()
        
        return {"status": "success", "message": "Đã xóa dự án thành công!"}
    except Exception as e:
        return {"status": "error", "message": f"Không thể xóa dự án: {str(e)}"}

@router.post("/api/score")
async def save_score(request: ScoreRequest):
    # Giữ nguyên logic lưu điểm của bạn
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
    # Giữ nguyên logic lấy dữ liệu dashboard của bạn
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
    res = supabase.table("history").select("percentage").eq("user_id", user_id).order("created_at", desc=True).limit(5).execute()
    if not res.data: return {"recommendation": "Chào mừng bạn! Hãy làm bài Quiz đầu tiên nhé."}
    avg_score = sum([r['percentage'] for r in res.data]) / len(res.data)
    try: return {"recommendation": call_groq(f"Nhận xét 2 câu cho học sinh đạt {avg_score}%\nVí dụ: Bạn đang làm tốt mảng lý thuyết. Hãy chú ý các câu hỏi bài tập áp dụng thực tế nhé.").strip()}
    except: return {"recommendation": "Chưa thể đưa ra nhận xét lúc này."}

@router.post("/api/notes")
async def add_note(request: NoteRequest):
    # ĐÃ SỬA: Lưu thêm notebook_id vào bảng dữ liệu
    supabase.table("notes").insert({
        "user_id": request.user_id, 
        "notebook_id": int(request.notebook_id),  # 👈 THÊM DÒNG NÀY
        "title": request.title, 
        "content": request.content
    }).execute()
    return {"status": "success"}

@router.get("/api/notes/{user_id}/{notebook_id}")
async def get_notes(user_id: str, notebook_id: int):
    # ĐÃ SỬA: Lọc thêm điều kiện eq("notebook_id", notebook_id)
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
        
        supabase.table("notes").update({
            "title": title, 
            "content": content
        }).eq("id", note_id).execute()
        
        return {"status": "success", "message": "Đã cập nhật ghi chú"}
    except Exception as e:
        return {"status": "error", "message": str(e)}