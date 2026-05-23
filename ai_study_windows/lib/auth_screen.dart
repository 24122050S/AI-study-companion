import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'workspace_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final String apiUrl = "http://localhost:8000";
  bool _isLoginMode = true; // True = Đăng nhập, False = Đăng ký
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitAuth() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showMessage("Vui lòng nhập đầy đủ thông tin", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final endpoint = _isLoginMode ? "/api/login" : "/api/register";
    try {
      final response = await http.post(
        Uri.parse("$apiUrl$endpoint"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        if (_isLoginMode) {
          // Lưu tên user vào bộ nhớ máy
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('username', data['username']);
          
          // 🔐 THÊM DÒNG NÀY ĐỂ LƯU TOKEN:
          await prefs.setString('token', data['token']); 
          
          if (!mounted) return;
          // Chuyển sang màn hình chính
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(
              builder: (context) => WorkspaceScreen(username: data['username'])
            )
          );
        } else {
          _showMessage("Đăng ký thành công! Hãy đăng nhập.", isError: false);
          setState(() => _isLoginMode = true); // Đổi sang tab đăng nhập
        }
      } else {
        _showMessage(data['detail'] ?? "Có lỗi xảy ra", isError: true);
      }
    } catch (e) {
      _showMessage("Không thể kết nối máy chủ", isError: true);
    }
    setState(() => _isLoading = false);
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
        child: Card(
          margin: const EdgeInsets.all(20),
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.school, size: 80, color: Colors.blueAccent),
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
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _submitAuth,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: Colors.orange,
                        ),
                        child: Text(_isLoginMode ? "ĐĂNG NHẬP" : "ĐĂNG KÝ", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                TextButton(
                  onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                  child: Text(_isLoginMode ? "Chưa có tài khoản? Đăng ký ngay" : "Đã có tài khoản? Đăng nhập", style: const TextStyle(color: Colors.blue)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}