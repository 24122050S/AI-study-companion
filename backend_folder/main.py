# ============================================================
#  FILE THAY THẾ: backend_folder/main.py
#  Thay đổi: nhúng thêm router concept_explain (giải thích node Mind Map bằng RAG)
# ============================================================
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware


# Nhúng các Router đã được chia nhỏ
# 🚀 MỚI: thêm concept_explain (giải thích node trên Sơ đồ tư duy bằng RAG)
from routers import auth, workspace, files, chat, study, concept_explain

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
app.include_router(concept_explain.router)  # 🚀 MỚI: API giải thích node Mind Map

@app.get("/")
async def root():
    return {"status": "online", "message": "Hệ thống đã được Module hóa thành công! 🚀"}
