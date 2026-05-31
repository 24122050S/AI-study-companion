from fastapi import APIRouter, HTTPException
import bcrypt
import jwt
from datetime import datetime, timedelta
from models import AuthRequest
from core import supabase
# Cập nhật dòng import này ở đầu file
from models import AuthRequest, RegisterRequest, ResetPasswordRequest

router = APIRouter()

SECRET_KEY = "CHIA_KHOA_BI_MAT_CUA_SANG_AI_STUDY" 
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7 

def hash_password(password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.now() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": int(expire.timestamp())})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

@router.post("/api/register")
async def register_user(request: RegisterRequest):
    try:
        exist_user = supabase.table("users").select("*").eq("username", request.username).execute()
        if exist_user.data:
            return {"detail": "Tên đăng nhập đã tồn tại!"}, 400
            
        supabase.table("users").insert({
            "username": request.username,
            "password": request.password,  
            "security_code": request.security_code 
        }).execute()
        
        return {"status": "success", "message": "Tạo tài khoản thành công!"}
    except Exception as e:
        return {"detail": str(e)}, 500

# 🚀 API ĐẶT LẠI MẬT KHẨU (Dùng ResetPasswordRequest)
@router.post("/api/reset_password")
async def reset_password(request: ResetPasswordRequest):
    try:
        user_match = supabase.table("users").select("*").eq("username", request.username).eq("security_code", request.security_code).execute()
            
        if not user_match.data:
            return {"status": "error", "message": "Tên đăng nhập hoặc Mã bảo mật không trùng khớp!"}
            
        supabase.table("users").update({
            "password": request.new_password
        }).eq("username", request.username).execute()
        
        return {"status": "success", "message": "Đặt lại mật khẩu mới thành công!"}
    except Exception as e:
        return {"status": "error", "message": f"Máy chủ gặp sự cố: {str(e)}"}

@router.post("/api/login")
async def login(request: AuthRequest):
    res = supabase.table("users").select("*").eq("username", request.username).execute()
    if not res.data: raise HTTPException(status_code=400, detail="Sai tên đăng nhập hoặc mật khẩu!")
    user = res.data[0]
    if not verify_password(request.password, user['password']):
        raise HTTPException(status_code=400, detail="Sai tên đăng nhập hoặc mật khẩu!")
    access_token = create_access_token(data={"sub": user['username']})
    return {"status": "success", "username": user['username'], "token": access_token}