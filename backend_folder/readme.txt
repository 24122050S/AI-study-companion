=============================================================================
                          HƯỚNG DẪN TRIỂN KHAI DỰ ÁN
                            AI STUDY COMPANION
=============================================================================

# THÔNG TIN TỔNG QUAN
- Tên dự án: Hệ thống Gia sư AI Cá nhân hóa (AI Study Companion).
- Mô tả: Ứng dụng hỗ trợ học tập tích hợp AI tạo sinh (RAG), bao gồm các chức năng: Chatbot phân tích tài liệu, Sinh đề thi (Trắc nghiệm, Đúng/Sai, Điền khuyết), Sơ đồ tư duy, Flashcard (thuật toán SRS), và Lộ trình học tập (Mastery Gate).
- Kiến trúc: Client-Server.
  + Frontend: Flutter (Dart).
  + Backend: FastAPI (Python).
  + Database & Storage: Supabase.
  + LLM Provider: Groq API (Llama-3-70b-versatile).
---------------------
#YÊU CẦU MÔI TRƯỜNG (PREREQUISITES)
1. Môi trường Backend:
   - Python 3.9 trở lên.
   - Trình quản lý gói pip.
   - Tài khoản Groq (để lấy API Key) và tài khoản Supabase (URL, Service Key).
2. Môi trường Frontend:
   - Flutter SDK (phiên bản ổn định mới nhất, >= 3.10.0).
   - Android Studio hoặc Visual Studio Code (cài đặt Flutter/Dart plugins).
   - Máy ảo Android Emulator, iOS Simulator hoặc trình duyệt Chrome (nếu chạy Web).

---------------------
#HƯỚNG DẪN CÀI ĐẶT VÀ TRIỂN KHAI BACKEND
Bước 1: Mở Terminal, di chuyển vào thư mục backend của dự án.
Bước 2: Cài đặt các thư viện Python cần thiết bằng lệnh:
        pip install fastapi uvicorn supabase groq edge-tts pydantic

Bước 3: Cấu hình biến môi trường (Environment Variables):
        - Mở file `core.py` (hoặc `.env` nếu có cấu hình riêng).
        - Điền các thông số xác thực:
          + GROQ_API_KEYS = ["your_groq_api_key_here"]
          + SUPABASE_URL = "your_supabase_project_url"
          + SUPABASE_KEY = "your_supabase_anon_or_service_key"

Bước 4: Khởi chạy máy chủ Backend:
        - Tại thư mục chứa file `main.py` (hoặc file gốc của ứng dụng), chạy lệnh:
          uvicorn main:app --host 0.0.0.0 --port 8000 --reload
        - Máy chủ sẽ lắng nghe tại: http://localhost:8000
        - Để kiểm tra API có hoạt động không, truy cập: http://localhost:8000/docs (Swagger UI).

---------------------
HƯỚNG DẪN CÀI ĐẶT VÀ TRIỂN KHAI FRONTEND
Bước 1: Mở Terminal mới, di chuyển vào thư mục frontend (thư mục Flutter).
Bước 2: Cài đặt các gói phụ thuộc (dependencies) bằng lệnh:
        flutter pub get

Bước 3: Cấu hình kết nối Backend:
        - Mở file `lib/api_constants.dart`.
        - Thay đổi biến `baseUrl` trỏ đến địa chỉ IP của Backend.
          + Nếu chạy trên máy ảo Android (Emulator): "http://10.0.2.2:8000"
          + Nếu chạy trên Web hoặc thiết bị thực (cùng mạng LAN): "http://<IP_IPv4_của_máy_tính>:8000"
          + Nếu chạy môi trường giả lập cục bộ Windows: "http://localhost:8000"

Bước 4: Biên dịch và chạy ứng dụng:
        - Sử dụng lệnh:
          flutter run hoặc flutter run -d <tên trình duyệt> (ví dụ: flutter run -d edge)
        - Hoặc nhấn nút "Run/Debug" trực tiếp trên VS Code / Android Studio.

---------------------
HƯỚNG DẪN THỰC THI (HƯỚNG DẪN SỬ DỤNG)
1. Upload Tài liệu: Tại màn hình chính, nhấn "Tải File Lên", chọn PDF/TXT. AI sẽ tự động phân tích và lưu vào cơ sở dữ liệu Vector (Supabase).
2. Lộ trình AI: Nhấn "Lộ trình AI", hệ thống sẽ tự động vạch ra các giai đoạn học. Giao diện sẽ bị khóa (focus) vào chủ đề hiện tại.
3. Tạo Quiz: Nhấn "Tạo Quiz", chọn số lượng và loại câu (Trắc nghiệm, Đúng/Sai, Điền khuyết). Cấu trúc sẽ được AI gen chuẩn theo định dạng THPT 2025.
4. Chấm điểm & Báo cáo: Nộp bài xong, nếu điểm < 80%, có thể nhấn "Bắt mạch điểm yếu". LLM sẽ phân tích lỗi sai và tạo đề khắc phục.
5. Sơ đồ tư duy: Bấm vào mục "Sơ đồ tư duy" để AI bóc tách các khái niệm và vẽ map quan hệ.

---------------------
NGUỒN TÀI LIỆU VÀ MÃ NGUỒN THAM KHẢO
1. Xử lý ngôn ngữ tự nhiên (LLM):
   - Groq API Documentation (Model: Llama-3-70b-versatile)
   - Prompt Engineering techniques (Zero-shot, Few-shot, Chain-of-Thought).

2. Xử lý giọng nói (Text-to-Speech):
   - Thư viện `edge-tts` (Microsoft Edge TTS API).

3. Thuật toán logic:
   - Spaced Repetition System (SRS) - Ứng dụng công thức SuperMemo-2 (SM-2) cho việc tính toán chu kỳ lặp lại thẻ Flashcard.
   - Retrieval-Augmented Generation (RAG) - Kỹ thuật truy xuất ngữ cảnh cho Chatbot.

4. Giao diện & Framework:
   - Flutter Documentation (https://docs.flutter.dev/)
   - FastAPI Documentation (https://fastapi.tiangolo.com/)
=============================================================================