import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'workspace_screen.dart';
import 'api_constants.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {

  bool _isLoginMode = true; 
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _securityCodeController = TextEditingController(); // 🚀 Ô nhập mã bảo mật
  
  bool _isLoading = false;

  Future<void> _submitAuth() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final securityCode = _securityCodeController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showMessage("Vui lòng nhập đầy đủ Tên và Mật khẩu", isError: true);
      return;
    }
    
    // Nếu là Đăng ký thì bắt buộc phải nhập mã bảo mật
    if (!_isLoginMode && securityCode.isEmpty) {
      _showMessage("Vui lòng tạo một Mã bảo mật để lấy lại tài khoản khi cần!", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final endpoint = _isLoginMode ? "/api/login" : "/api/register";
    try {
      final bodyData = {
        "username": username, 
        "password": password,
      };
      
      // Đăng ký thì mới gửi kèm mã bảo mật
      if (!_isLoginMode) {
        bodyData["security_code"] = securityCode;
      }

      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}$endpoint"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(bodyData),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        if (_isLoginMode) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('username', data['username']);
          await prefs.setString('token', data['token'] ?? ''); 
          
          if (!mounted) return;
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(
              builder: (context) => WorkspaceScreen(username: data['username'])
            )
          );
        } else {
          _showMessage("Đăng ký thành công! Hãy đăng nhập.", isError: false);
          setState(() {
            _isLoginMode = true; 
            _securityCodeController.clear(); // Xóa mã bảo mật sau khi đăng ký xong
          }); 
        }
      } else {
        _showMessage(data['detail'] ?? "Có lỗi xảy ra", isError: true);
      }
    } catch (e) {
      _showMessage("Không thể kết nối máy chủ", isError: true);
    }
    setState(() => _isLoading = false);
  }

  // 🚀 HỘP THOẠI QUÊN MẬT KHẨU
  void _showForgotPasswordDialog() {
    final TextEditingController recoverUserCtrl = TextEditingController();
    final TextEditingController recoverCodeCtrl = TextEditingController();
    final TextEditingController newPassCtrl = TextEditingController();
    bool isRecovering = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.lock_reset, color: Colors.orange, size: 28),
                SizedBox(width: 10),
                Text("Khôi phục Mật khẩu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Vui lòng nhập Tên đăng nhập và Mã bảo mật lúc tạo tài khoản để đặt lại mật khẩu mới.", style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 15),
                TextField(
                  controller: recoverUserCtrl,
                  decoration: const InputDecoration(labelText: "Tên đăng nhập", prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: recoverCodeCtrl,
                  decoration: const InputDecoration(labelText: "Mã bảo mật", prefixIcon: Icon(Icons.shield), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Mật khẩu mới", prefixIcon: Icon(Icons.key), border: OutlineInputBorder()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text("Hủy bỏ", style: TextStyle(color: Colors.grey))
              ),
              isRecovering
                  ? const CircularProgressIndicator(color: Colors.orange)
                  : ElevatedButton(
                      onPressed: () async {
                        if (recoverUserCtrl.text.isEmpty || recoverCodeCtrl.text.isEmpty || newPassCtrl.text.isEmpty) {
                          _showMessage("Vui lòng nhập đủ thông tin!", isError: true);
                          return;
                        }
                        
                        setDialogState(() => isRecovering = true);
                        try {
                          final response = await http.post(
                            Uri.parse("${ApiConstants.baseUrl}/api/reset_password"),
                            headers: {"Content-Type": "application/json"},
                            body: jsonEncode({
                              "username": recoverUserCtrl.text.trim(),
                              "security_code": recoverCodeCtrl.text.trim(),
                              "new_password": newPassCtrl.text.trim()
                            }),
                          );
                          
                          final data = jsonDecode(utf8.decode(response.bodyBytes));
                          if (data['status'] == 'success') {
                            Navigator.pop(context); // Tắt hộp thoại
                            _showMessage("Đổi mật khẩu thành công! Bạn có thể đăng nhập.", isError: false);
                          } else {
                            _showMessage(data['message'] ?? "Lỗi sai thông tin", isError: true);
                          }
                        } catch (e) {
                          _showMessage("Lỗi kết nối máy chủ", isError: true);
                        }
                        setDialogState(() => isRecovering = false);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      child: const Text("Xác nhận đổi", style: TextStyle(color: Colors.white)),
                    )
            ],
          );
        }
      )
    );
  }

  void _showMessage(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueAccent,
      body: Center(
        child: SingleChildScrollView(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.school, size: 80, color: Colors.blueAccent),
                  const SizedBox(height: 10),
                  Text(_isLoginMode ? "Chào mừng trở lại!" : "Tạo tài khoản mới", 
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: "Tên đăng nhập", prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Mật khẩu", prefixIcon: Icon(Icons.lock), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),

                  // 🚀 Ô NHẬP MÃ BẢO MẬT (Chỉ hiện khi đang ở chế độ Đăng Ký)
                  if (!_isLoginMode) ...[
                    TextField(
                      controller: _securityCodeController,
                      decoration: const InputDecoration(
                        labelText: "Mã bảo mật (Dùng để khôi phục mk)", 
                        prefixIcon: Icon(Icons.security), 
                        border: OutlineInputBorder()
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  
                  // 🚀 NÚT QUÊN MẬT KHẨU (Chỉ hiện khi ở chế độ Đăng nhập)
                  if (_isLoginMode)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: const Text("Quên mật khẩu?", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    
                  if (!_isLoginMode && _isLoginMode) const SizedBox(height: 20),

                  _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _submitAuth,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                          child: Text(_isLoginMode ? "ĐĂNG NHẬP" : "ĐĂNG KÝ", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                  
                  const SizedBox(height: 10),

                  TextButton(
                    onPressed: () => setState(() {
                      _isLoginMode = !_isLoginMode;
                      // Reset lại các ô chữ khi đổi chế độ
                      _usernameController.clear();
                      _passwordController.clear();
                      _securityCodeController.clear();
                    }),
                    child: Text(_isLoginMode ? "Chưa có tài khoản? Đăng ký ngay" : "Đã có tài khoản? Đăng nhập", style: const TextStyle(color: Colors.blue)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}