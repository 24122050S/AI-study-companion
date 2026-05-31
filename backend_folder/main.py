from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware


# Nhúng các Router đã được chia nhỏ
from routers import auth, workspace, files, chat, study

app = FastAPI(title="AI Study Companion API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Gắn các mảnh ghép (Module) vào file chạy chính
app.include_router(auth.router)
app.include_router(files.router)
app.include_router(chat.router)
app.include_router(study.router)
app.include_router(workspace.router)

@app.get("/")
async def root():
    return {"status": "online", "message": "Hệ thống đã được Module hóa thành công! 🚀"}