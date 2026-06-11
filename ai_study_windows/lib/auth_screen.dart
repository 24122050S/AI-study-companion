import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'workspace_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- Palette màu Indigo mới (#A5B4FC) ---
const Color cBg         = Color(0xFFA5B4FC);
const Color cIndigoDark = Color(0xFF6366F1);
const Color cIndigoMid  = Color(0xFF818CF8);
const Color cBlack      = Color(0xFF1E293B);
const Color cWhite      = Color(0xFFFFFFFF);
const Color cCoral      = Color(0xFFFF5B64);
const Color cMint       = Color(0xFF34D399);
const Color cFormBg     = Color(0xFFF8FAFF);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  // Thay đổi URL nếu bạn đang dùng ApiConstants.baseUrl
  final String apiUrl = "http://localhost:8000"; 
  bool _isLoginMode = true;
  
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _securityCodeCtrl = TextEditingController(); // Ô nhập mã bảo mật
  
  bool _isLoading = false;

  late AnimationController _floatCtrl1;
  late AnimationController _floatCtrl2;

  @override
  void initState() {
    super.initState();
    _floatCtrl1 = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _floatCtrl2 = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatCtrl1.dispose();
    _floatCtrl2.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _securityCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitAuth() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final securityCode = _securityCodeCtrl.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showMsg("Vui lòng nhập đầy đủ Tên và Mật khẩu", isError: true);
      return;
    }

    // Nếu là Đăng ký thì bắt buộc phải nhập mã bảo mật
    if (!_isLoginMode && securityCode.isEmpty) {
      _showMsg("Vui lòng tạo một Mã bảo mật để lấy lại tài khoản khi cần!", isError: true);
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
        Uri.parse("$apiUrl$endpoint"),
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
              context, MaterialPageRoute(builder: (_) => WorkspaceScreen(username: data['username'])));
        } else {
          _showMsg("Đăng ký thành công! Hãy đăng nhập.", isError: false);
          setState(() {
            _isLoginMode = true;
            _securityCodeCtrl.clear(); // Xóa mã bảo mật sau khi đăng ký xong
          });
        }
      } else {
        _showMsg(data['detail'] ?? "Có lỗi xảy ra", isError: true);
      }
    } catch (_) {
      _showMsg("Không thể kết nối máy chủ", isError: true);
    }
    setState(() => _isLoading = false);
  }

  // ── HỘP THOẠI QUÊN MẬT KHẨU ───────────────────────────────────────────────
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
            backgroundColor: cWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.lock_reset, color: cIndigoDark, size: 28),
                SizedBox(width: 10),
                Text("Khôi phục Mật khẩu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cBlack)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Vui lòng nhập Tên đăng nhập và Mã bảo mật lúc tạo tài khoản để đặt lại mật khẩu mới.", style: TextStyle(fontSize: 14, color: cBlack.withOpacity(0.6))),
                const SizedBox(height: 15),
                TextField(
                  controller: recoverUserCtrl,
                  decoration: InputDecoration(
                    labelText: "Tên đăng nhập", 
                    prefixIcon: const Icon(Icons.person, color: cIndigoMid), 
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: recoverCodeCtrl,
                  decoration: InputDecoration(
                    labelText: "Mã bảo mật", 
                    prefixIcon: const Icon(Icons.shield, color: cIndigoMid), 
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "Mật khẩu mới", 
                    prefixIcon: const Icon(Icons.key, color: cIndigoMid), 
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: Text("Hủy bỏ", style: TextStyle(color: cBlack.withOpacity(0.5)))
              ),
              isRecovering
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: cIndigoDark, strokeWidth: 2)),
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        if (recoverUserCtrl.text.isEmpty || recoverCodeCtrl.text.isEmpty || newPassCtrl.text.isEmpty) {
                          _showMsg("Vui lòng nhập đủ thông tin!", isError: true);
                          return;
                        }
                        
                        setDialogState(() => isRecovering = true);
                        try {
                          final response = await http.post(
                            Uri.parse("$apiUrl/api/reset_password"),
                            headers: {"Content-Type": "application/json"},
                            body: jsonEncode({
                              "username": recoverUserCtrl.text.trim(),
                              "security_code": recoverCodeCtrl.text.trim(),
                              "new_password": newPassCtrl.text.trim()
                            }),
                          );
                          
                          final data = jsonDecode(utf8.decode(response.bodyBytes));
                          if (data['status'] == 'success') {
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            _showMsg("Đổi mật khẩu thành công! Bạn có thể đăng nhập.", isError: false);
                          } else {
                            _showMsg(data['message'] ?? "Lỗi sai thông tin", isError: true);
                          }
                        } catch (e) {
                          _showMsg("Lỗi kết nối máy chủ", isError: true);
                        }
                        setDialogState(() => isRecovering = false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cIndigoDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                      ),
                      child: const Text("Xác nhận đổi", style: TextStyle(color: cWhite)),
                    )
            ],
          );
        }
      )
    );
  }

  void _showMsg(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, color: cWhite)),
      backgroundColor: isError ? cCoral : cMint,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;
    return Scaffold(
      backgroundColor: cBg,
      body: isDesktop ? _buildDesktop(size) : _buildMobile(size),
    );
  }

  // ── DESKTOP ───────────────────────────────────────────────────────────────
  Widget _buildDesktop(Size size) {
    return Row(
      children: [
        SizedBox(
          width: size.width * 0.35, 
          child: Container(
            color: cFormBg,
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLogo(),
                const Spacer(),
                Center(child: _buildFormContent()),
                const Spacer(),
              ],
            ),
          ),
        ),
        Expanded(
          child: Container(
            color: cBg,
            child: Stack(
              children: [
                Positioned(
                  top: -80, right: -80,
                  child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: cIndigoDark.withOpacity(0.18))),
                ),
                Positioned(
                  bottom: -60, left: -60,
                  child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: cIndigoDark.withOpacity(0.12))),
                ),
                Center(
                  child: AnimatedBuilder(
                    animation: _floatCtrl1,
                    builder: (_, child) {
                      final dy = math.sin(_floatCtrl1.value * math.pi * 2) * 12;
                      return Transform.translate(offset: Offset(0, dy), child: child);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset('assets/images/pg1.png', width: size.width * 0.38, fit: BoxFit.cover),
                    ),
                  ),
                ),
                Positioned(top: size.height * 0.15, left: 60, child: _buildFloatingDecor(_floatCtrl1, Icons.auto_awesome_rounded, const Color(0xFFFFD166), 32)),
                Positioned(top: size.height * 0.25, right: 50, child: _buildFloatingDecor(_floatCtrl2, Icons.school_rounded, cWhite.withOpacity(0.7), 28)),
                Positioned(bottom: size.height * 0.28, left: 40, child: _buildFloatingDecor(_floatCtrl2, Icons.lightbulb_rounded, cMint.withOpacity(0.8), 30)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingDecor(AnimationController ctrl, IconData icon, Color color, double size) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final dy = math.sin(ctrl.value * math.pi * 2) * 10;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Container(
            width: size + 16, height: size + 16,
            decoration: BoxDecoration(color: cWhite.withOpacity(0.25), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: size * 0.7),
          ),
        );
      },
    );
  }

  // ── MOBILE ────────────────────────────────────────────────────────────────
  Widget _buildMobile(Size size) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            height: 260, width: double.infinity, color: cBg,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: -40, right: -40,
                  child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, color: cIndigoDark.withOpacity(0.2))),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset('assets/images/pg1.png', height: 200, fit: BoxFit.cover),
                ),
              ],
            ),
          ),
          Container(
            color: cFormBg,
            padding: const EdgeInsets.all(30),
            child: Column(
              children: [
                _buildLogo(),
                const SizedBox(height: 24),
                _buildFormContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── LOGO ──────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return Row(
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: cIndigoDark, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.auto_stories, color: cWhite, size: 22),
        ),
        const SizedBox(width: 10),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(text: "Learn", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cBlack, letterSpacing: 0.5)),
              TextSpan(text: "ify", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cIndigoDark, letterSpacing: 0.5)),
            ],
          ),
        ),
      ],
    );
  }

  // ── FORM ──────────────────────────────────────────────────────────────────
  Widget _buildFormContent() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isLoginMode ? "Welcome Back 👋" : "Create Account",
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: cBlack),
          ),
          const SizedBox(height: 8),
          Text(
            "Học tập không giới hạn cùng AI Companion.",
            style: TextStyle(color: cBlack.withOpacity(0.45), fontSize: 14),
          ),
          const SizedBox(height: 36),
          
          _buildTextField(_usernameCtrl, "Username", Icons.alternate_email),
          const SizedBox(height: 18),
          
          _buildTextField(_passwordCtrl, "Password", Icons.lock_open, isPass: true),
          
          // Ô nhập mã bảo mật chỉ hiện khi đăng ký
          if (!_isLoginMode) ...[
            const SizedBox(height: 18),
            _buildTextField(_securityCodeCtrl, "Mã bảo mật (Dùng khôi phục MK)", Icons.security_rounded),
          ],
          
          const SizedBox(height: 10),
          
          // Nút quên mật khẩu chỉ hiện khi đăng nhập
          if (_isLoginMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _showForgotPasswordDialog,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  "Quên mật khẩu?",
                  style: TextStyle(fontSize: 13, color: cIndigoDark, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          
          const SizedBox(height: 32),
          
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: cIndigoDark))
              : SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _submitAuth,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cBlack,
                      foregroundColor: cWhite,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLoginMode ? "Sign In" : "Sign Up",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
          
          const SizedBox(height: 24),
          
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _isLoginMode = !_isLoginMode;
                _usernameCtrl.clear();
                _passwordCtrl.clear();
                _securityCodeCtrl.clear();
              }),
              child: RichText(
                text: TextSpan(
                  text: _isLoginMode ? "Chưa có tài khoản? " : "Đã có tài khoản? ",
                  style: TextStyle(color: cBlack.withOpacity(0.45), fontSize: 13),
                  children: [
                    TextSpan(
                      text: _isLoginMode ? "Đăng ký ngay" : "Đăng nhập",
                      style: const TextStyle(color: cIndigoDark, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint, IconData icon, {bool isPass = false}) {
    return TextField(
      controller: ctrl,
      obscureText: isPass,
      style: const TextStyle(color: cBlack, fontSize: 14, fontWeight: FontWeight.w500),
      cursorColor: cIndigoDark,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: cIndigoMid, size: 20),
        hintText: hint,
        hintStyle: TextStyle(color: cBlack.withOpacity(0.35), fontSize: 14),
        filled: true,
        fillColor: cWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0DEFF), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0DEFF), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cIndigoDark, width: 2),
        ),
      ),
    );
  }
}