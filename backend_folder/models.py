from pydantic import BaseModel
from typing import Optional

class ChatRequest(BaseModel):
    user_id: str
    notebook_id: str
    message: str
    focus_topic: Optional[str] = None

class ScoreRequest(BaseModel):
    user_id: str
    notebook_id: str
    topic: str
    score: int
    total: int

class WeaknessRequest(BaseModel):
    user_id: str
    notebook_id: str
    wrong_questions: list

# Dùng cho API đăng nhập bình thường
class AuthRequest(BaseModel):
    username: str
    password: str

# 🚀 THÊM MỚI: Dùng cho API Đăng ký (Có mã bảo mật)
class RegisterRequest(BaseModel):
    username: str
    password: str
    security_code: str

# 🚀 THÊM MỚI: Dùng cho API Quên mật khẩu
class ResetPasswordRequest(BaseModel):
    username: str
    security_code: str
    new_password: str

class NoteRequest(BaseModel):
    user_id: str
    notebook_id: str
    title: str
    content: str

class NotebookRequest(BaseModel):
    user_id: str
    title: str