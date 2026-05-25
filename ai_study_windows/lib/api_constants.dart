class ApiConstants {
  // Đổi địa chỉ ở đây thì TOÀN BỘ App sẽ tự động cập nhật theo! 
  // Dành cho chạy trên Web hoặc Windows:
  static const String baseUrl = "http://localhost:8000"; 
  
  // 💡 Mẹo: Nếu sau này bạn chạy trên Máy ảo Android (Emulator), 
  // bạn sẽ phải đổi thành dòng dưới đây vì Android không hiểu localhost:
  // static const String baseUrl = "http://10.0.2.2:8000"; 

  // Nếu sau này deploy lên server thật, chỉ cần đổi thành:
  // static const String baseUrl = "https://ten-mien-cua-ban.com";
}