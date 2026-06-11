// 🔧 SỬA LỖI: File test mặc định của Flutter gọi `const MyApp()` nhưng MyApp
// của project yêu cầu tham số bắt buộc `startScreen` → chạy `flutter test`
// sẽ báo LỖI BIÊN DỊCH ngay lập tức. Test cũ còn kiểm tra bộ đếm (counter)
// vốn không tồn tại trong app này.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_study_windows/main.dart';

void main() {
  testWidgets('App khởi động được với màn hình bất kỳ', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(
      startScreen: Scaffold(body: Text('Test Screen')),
    ));

    expect(find.text('Test Screen'), findsOneWidget);
  });
}
