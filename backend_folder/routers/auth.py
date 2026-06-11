from fastapi import APIRouter, HTTPException
import bcrypt
import jwt
import os
from datetime import datetime, timedelta
from core import supabase
from models import AuthRequest, RegisterRequest, ResetPasswordRequest

router = APIRouter()

# 🔧 SỬA LỖI BẢO MẬT: Đọc SECRET_KEY từ biến môi trường (.env), chỉ dùng giá trị mặc định khi dev
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "CHIA_KHOA_BI_MAT_CUA_SANG_AI_STUDY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7

def hash_password(password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    # 🔧 SỬA LỖI: bcrypt.checkpw sẽ NÉM EXCEPTION (Invalid salt) nếu trong DB
    # đang lưu mật khẩu thô (plaintext) → trước đây làm API login sập 500.
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except (ValueError, TypeError):
        return False

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.now() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": int(expire.timestamp())})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

@router.post("/api/register")
async def register_user(request: RegisterRequest):
    try:
        exist_user = supabase.table("users").select("id").eq("username", request.username).execute()
        if exist_user.data:
            # 🔧 SỬA LỖI: Trước đây viết `return {...}, 400` → FastAPI trả về MẢNG JSON
            # với status 200, khiến App tưởng đăng ký THÀNH CÔNG dù username đã trùng!
            raise HTTPException(status_code=400, detail="Tên đăng nhập đã tồn tại!")

        supabase.table("users").insert({
            "username": request.username,
            # 🔧 SỬA LỖI NGHIÊM TRỌNG NHẤT: Trước đây lưu mật khẩu THÔ (request.password)
            # nhưng /api/login lại so sánh bằng bcrypt → KHÔNG AI ĐĂNG NHẬP ĐƯỢC sau khi đăng ký.
            "password": hash_password(request.password),
            "security_code": request.security_code
        }).execute()

        return {"status": "success", "message": "Tạo tài khoản thành công!"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Máy chủ gặp sự cố: {str(e)}")

@router.post("/api/reset_password")
async def reset_password(request: ResetPasswordRequest):
    try:
        user_match = supabase.table("users").select("id").eq("username", request.username).eq("security_code", request.security_code).execute()

        if not user_match.data:
            return {"status": "error", "message": "Tên đăng nhập hoặc Mã bảo mật không trùng khớp!"}

        supabase.table("users").update({
            # 🔧 SỬA LỖI: Mật khẩu mới cũng phải được hash, nếu không sẽ lại không đăng nhập được
            "password": hash_password(request.new_password)
        }).eq("username", request.username).execute()

        return {"status": "success", "message": "Đặt lại mật khẩu mới thành công!"}
    except Exception as e:
        return {"status": "error", "message": f"Máy chủ gặp sự cố: {str(e)}"}

@router.post("/api/login")
async def login(request: AuthRequest):
    res = supabase.table("users").select("*").eq("username", request.username).execute()
    if not res.data:
        raise HTTPException(status_code=400, detail="Sai tên đăng nhập hoặc mật khẩu!")
    user = res.data[0]

    if not verify_password(request.password, user['password']):
        # 🔧 HỖ TRỢ TÀI KHOẢN CŨ: Nếu DB còn tài khoản lưu mật khẩu thô (do bug cũ),
        # so sánh trực tiếp và tự động nâng cấp lên hash để lần sau an toàn.
        if user['password'] == request.password:
            supabase.table("users").update({
                "password": hash_password(request.password)
            }).eq("username", user['username']).execute()
        else:
            raise HTTPException(status_code=400, detail="Sai tên đăng nhập hoặc mật khẩu!")

    access_token = create_access_token(data={"sub": user['username']})
    return {"status": "success", "username": user['username'], "token": access_token}
