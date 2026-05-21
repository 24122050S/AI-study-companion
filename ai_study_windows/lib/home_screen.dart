import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:audioplayers/audioplayers.dart'; // THƯ VIỆN AUDIO MỚI

import 'quiz_screen.dart';
import 'note_screen.dart';
import 'history_screen.dart';
import 'flashcard_screen.dart';
import 'auth_screen.dart';
import 'roadmap_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isChatLoading = false;

  List<dynamic> _uploadedFiles = [];
  bool _isFilesLoading = false;

  // --- THÔNG SỐ GAMIFICATION ---
  int _streak = 0;
  List<dynamic> _notifications = [];
  int _unreadCount = 0;

  // --- TRÌNH PHÁT NHẠC (ĐỌC GIỌNG AI EDGE TTS) ---
  final AudioPlayer _audioPlayer = AudioPlayer();

  String _username = "An Nguyen"; 
  final String apiUrl = "http://10.0.195.105:8000"; 

  @override
  void initState() {
    super.initState();
    _loadUser();
    _messages.add({
      "sender": "ai", 
      "text": "Xin chào! Mình là AI Companion. Bạn hãy tải tài liệu lên và hỏi mình bất cứ điều gì nhé! 🤖"
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose(); // Giải phóng bộ nhớ của Audio
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- HÀM PHÁT GIỌNG NÓI (GỌI API PYTHON ĐỂ LẤY EDGE TTS) ---
  Future<void> _speak(String text) async {
    // 1. Dọn dẹp ký tự thừa Markdown
    String cleanText = text.replaceAll(RegExp(r'[*#_`]'), ''); 
    
    // 2. Gắn chữ vào đường dẫn API của Backend Python
    String ttsUrl = "$apiUrl/api/tts?text=${Uri.encodeComponent(cleanText)}";
    
    // 3. Phát âm thanh
    await _audioPlayer.play(UrlSource(ttsUrl));
  }

  Future<void> _quickSaveNote(String content) async {
    try {
      final response = await http.post(
        Uri.parse("$apiUrl/api/notes"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": _username, "title": "Kiến thức từ AI", "content": content}),
      );
      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Đã lưu vào Sổ tay!"), backgroundColor: Colors.teal));
      }
    } catch (e) { print(e); }
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username') ?? "An Nguyen";
    });
    _fetchFiles(); 
    _fetchDashboardStats(); 
  }

  Future<void> _fetchDashboardStats() async {
    try {
      final response = await http.get(Uri.parse("$apiUrl/api/dashboard/$_username"));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _streak = data['streak'] ?? 0;
          _notifications = data['notifications'] ?? [];
          _unreadCount = _notifications.length; 
        });
      }
    } catch (e) {
      print("Lỗi tải thông báo: $e");
    }
  }

  void _openNotifications() {
    setState(() => _unreadCount = 0); 
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text("Trung tâm thông báo", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: 400,
          height: 350,
          child: _notifications.isEmpty
              ? const Center(child: Text("Không có thông báo nào."))
              : ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final n = _notifications[index];
                    
                    IconData icon; Color color;
                    if (n['type'] == 'success') { icon = Icons.stars; color = Colors.green; }
                    else if (n['type'] == 'danger') { icon = Icons.warning_rounded; color = Colors.red; }
                    else if (n['type'] == 'warning') { icon = Icons.flag; color = Colors.orange; }
                    else { icon = Icons.info; color = Colors.blue; }

                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
                        title: Text(n['message'], style: const TextStyle(fontSize: 14)),
                        subtitle: Text(n['time'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Đóng", style: TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Future<void> _fetchFiles() async {
    setState(() => _isFilesLoading = true);
    try {
      final response = await http.get(Uri.parse("$apiUrl/api/files/$_username"));
      if (response.statusCode == 200) {
        setState(() => _uploadedFiles = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) { print(e); }
    setState(() => _isFilesLoading = false);
  }

  Future<void> _deleteFile(int fileId) async {
    try {
      final response = await http.delete(Uri.parse("$apiUrl/api/files/$fileId"));
      if (response.statusCode == 200) {
        _fetchFiles(); 
        if (!mounted) return; 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa tài liệu khỏi danh sách!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.grey));
      }
    } catch (e) { print(e); }
  }

  Future<void> _uploadPDF() async {
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang gửi file cho AI học...')));

    try {
      final request = http.MultipartRequest('POST', Uri.parse('$apiUrl/api/upload'));
      request.fields['user_id'] = _username;
      
      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes('file', result.files.single.bytes!, filename: result.files.single.name));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', result.files.single.path!));
      }
      
      final response = await request.send();
      if (response.statusCode == 200) {
        _fetchFiles(); 
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ AI đã học xong tài liệu!'), backgroundColor: Colors.green));
      }
    } catch (e) { print(e); }
  }

  Future<void> _sendChatMessage() async {
    String text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({"sender": "user", "text": text});
      _messages.add({"sender": "ai", "text": "Đang suy nghĩ..."}); 
      _isChatLoading = true;
      _chatController.clear();
    });
    
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse("$apiUrl/api/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": _username, "message": text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _messages.removeLast(); 
          _messages.add({"sender": "ai", "text": data["data"]["content"]});
        });
      } else {
        setState(() {
          _messages.removeLast();
          _messages.add({"sender": "ai", "text": "Hệ thống bận hoặc bạn chưa tải PDF lên!"});
        });
      }
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add({"sender": "ai", "text": "Lỗi kết nối máy chủ."});
      });
    } finally {
      setState(() => _isChatLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB), 
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                children: [
                  Expanded(flex: 2, child: _buildLeftPanel()),
                  const SizedBox(width: 24),
                  Expanded(flex: 4, child: _buildChatPanel()),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: _buildRightPanel()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_stories, color: Colors.indigo, size: 30),
          const SizedBox(width: 15),
          const Text("AI STUDY COMPANION", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
          const Spacer(),
          
          _buildBadge(Icons.local_fire_department, "$_streak ngày", _streak > 0 ? Colors.orange : Colors.grey),
          const SizedBox(width: 20),
          
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, color: Colors.grey, size: 28),
                onPressed: _openNotifications, 
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('$_unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                )
            ],
          ),
          
          const SizedBox(width: 20),


          ////
          PopupMenuButton<String>(
            offset: const Offset(0, 45), // Canh chỉnh menu rớt xuống vừa vặn
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            tooltip: 'Tùy chọn tài khoản',
            onSelected: (value) async {
              if (value == 'logout') {
                // 1. Xóa phiên đăng nhập (Hủy session)
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('username');
                
                // 2. Đá người dùng về màn hình Login và xóa sạch lịch sử trang (không cho back lại)
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                  (route) => false,
                );
              }
            },
            child: Row(
              children: [
                Text(_username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(width: 10),
                const CircleAvatar(
                  radius: 18, 
                  backgroundColor: Colors.blueAccent, 
                  child: Icon(Icons.person, color: Colors.white, size: 20)
                ),
                const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
              ],
            ),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent),
                    SizedBox(width: 12),
                    Text('Đăng xuất', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return _buildPanelContainer(
      title: "Tài liệu tải lên",
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: _uploadPDF,
            icon: const Icon(Icons.upload_file),
            label: const Text("Tải lên PDF", style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5DBB93),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          const Align(alignment: Alignment.centerLeft, child: Text("PDF đã tải lên", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          const SizedBox(height: 10),
          
          Expanded(
            child: _isFilesLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF5DBB93)))
              : _uploadedFiles.isEmpty
                ? const Center(child: Text("Chưa có tài liệu nào.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _uploadedFiles.length,
                    itemBuilder: (context, index) {
                      final file = _uploadedFiles[index];
                      return _buildFileRow(file['id'], file['filename']); 
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPanel() {
    return _buildPanelContainer(
      title: "Chat with AI",
      child: Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF1F6F9), borderRadius: BorderRadius.circular(15)),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final m = _messages[index];
                  bool isAi = m['sender'] == 'ai';
                  return Align(
                    alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(16),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.4),
                      decoration: BoxDecoration(
                        color: isAi ? Colors.white : const Color(0xFF6C63FF),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                      ),
                      child: isAi 
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MarkdownBody(
                                data: m['text']!,
                                styleSheet: MarkdownStyleSheet(
                                  p: const TextStyle(fontSize: 15, color: Colors.black87),
                                ),
                              ),
                              if (m['text'] != "Đang suy nghĩ...") ...[
                                const SizedBox(height: 10),
                                const Divider(color: Colors.black12, height: 1),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.volume_up, size: 20, color: Colors.orange),
                                      tooltip: 'Đọc câu trả lời',
                                      onPressed: () => _speak(m['text']!), 
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.bookmark_add_outlined, size: 20, color: Colors.teal),
                                      tooltip: 'Lưu vào sổ tay',
                                      onPressed: () => _quickSaveNote(m['text']!),
                                    ),
                                  ],
                                )
                              ]
                            ],
                          )
                        : Text(m['text']!, style: const TextStyle(color: Colors.white, fontSize: 15)),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  onSubmitted: (_) => _sendChatMessage(),
                  decoration: InputDecoration(
                    hintText: "Hỏi AI về bài học...",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                backgroundColor: const Color(0xFF6C63FF),
                child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendChatMessage),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return _buildPanelContainer(
      title: "Chức năng",
      child: ListView(
        children: [
          _buildActionItem("Lộ trình học AI", Icons.map, const Color(0xFFFFF3E0), Colors.deepOrange, () {
             Navigator.push(context, MaterialPageRoute(builder: (context) => RoadmapScreen(username: _username)));
          }),
          _buildActionItem("Tạo Quiz", Icons.settings_suggest, const Color(0xFFE3F9F1), Colors.teal, () {
            _showQuizSettingsDialog(); // Hiện bảng tùy chọn
          }),
          _buildActionItem("Phòng thi ảo", Icons.timer, const Color(0xFFEBF3FF), Colors.blueAccent, () async {
             await Navigator.push(context, MaterialPageRoute(builder: (context) => QuizScreen(modeName: "Phòng thi ảo", numQuestions: 20, timeLimit: 900, username: _username)));
             _fetchDashboardStats(); 
          }),
          _buildActionItem("Flashcards", Icons.style, const Color(0xFFF3EFFF), Colors.purple, () {
             Navigator.push(context, MaterialPageRoute(builder: (context) => FlashcardScreen(username: _username)));
          }),
          _buildActionItem("Sổ tay ghi nhớ", Icons.book, const Color(0xFFE8F5E9), Colors.green, () {
             Navigator.push(context, MaterialPageRoute(builder: (context) => NoteScreen(username: _username)));
          }),
          _buildActionItem("Bảng điểm & Xếp hạng", Icons.emoji_events, const Color(0xFFFFF8E1), Colors.orange, () {
             Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(username: _username)));
          }),
        ],
      ),
    );
  }

  Widget _buildPanelContainer({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildFileRow(int id, String name) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf, color: Color(0xFF6C63FF), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: name,
              child: Text(name, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _deleteFile(id),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(String label, IconData icon, Color bg, Color iconCol, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        tileColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: iconCol),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text, Color col) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: col.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [Icon(icon, color: col, size: 18), const SizedBox(width: 5), Text(text, style: TextStyle(color: col, fontWeight: FontWeight.bold))]),
    );
  }
  // HÀM HIỂN THỊ BẢNG CHỌN SỐ CÂU HỎI VÀ ĐỘ KHÓ
  Future<void> _showQuizSettingsDialog() async {
    int selectedNum = 5;
    String selectedDiff = "Trung bình";

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.tune, color: Colors.teal),
                  SizedBox(width: 10),
                  Text("Tùy chỉnh Bộ đề", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Số lượng câu hỏi:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: selectedNum,
                        isExpanded: true,
                        items: [5, 10, 15, 20, 30].map((e) => DropdownMenuItem(value: e, child: Text("$e câu hỏi"))).toList(),
                        onChanged: (val) => setDialogState(() => selectedNum = val!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("Mức độ khó:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedDiff,
                        isExpanded: true,
                        items: ["Dễ", "Trung bình", "Khó"].map((e) => DropdownMenuItem(value: e, child: Text("Mức độ $e"))).toList(),
                        onChanged: (val) => setDialogState(() => selectedDiff = val!),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy bỏ", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context); // Đóng bảng chọn
                    // Chuyển sang màn hình thi
                    await Navigator.push(context, MaterialPageRoute(
                      builder: (context) => QuizScreen(
                        modeName: "Quiz ($selectedDiff)", 
                        numQuestions: selectedNum, 
                        timeLimit: 0, 
                        username: _username,
                        difficulty: selectedDiff, // Gửi độ khó sang QuizScreen
                      )
                    ));
                    _fetchDashboardStats(); 
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("Bắt đầu thi"),
                )
              ],
            );
          }
        );
      }
    );
  }
}