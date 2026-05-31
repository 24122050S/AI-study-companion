import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:audioplayers/audioplayers.dart'; 
import 'dart:async';

import 'quiz_screen.dart';
import 'note_screen.dart';
import 'history_screen.dart';
import 'flashcard_screen.dart';
import 'auth_screen.dart';
import 'roadmap_screen.dart';
import 'api_constants.dart';
import 'quiz_history_screen.dart'; 
import 'flashcard_history_screen.dart';
import 'study_history_screen.dart'; 
import 'concept_map_screen.dart';

class HomeScreen extends StatefulWidget {
  final String notebookId;    
  final String notebookTitle; 

  const HomeScreen({
    super.key, 
    required this.notebookId, 
    required this.notebookTitle
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

String? _focusTopic; 
Timer? _roadmapTimer;
int _roadmapRemainingSeconds = 0;

String _formatTime(int seconds) {
  int m = seconds ~/ 60;
  int s = seconds % 60;
  return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isChatLoading = false;

  List<dynamic> _uploadedFiles = [];
  bool _isFilesLoading = false;

  int _streak = 0;
  List<dynamic> _notifications = [];
  int _unreadCount = 0;

  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingText;

  String _username = "An Nguyen"; 
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUser();

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) setState(() => _currentlyPlayingText = null);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioPlayer.dispose(); 
    _chatController.dispose();
    _scrollController.dispose();
    _roadmapTimer?.cancel(); 
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      _roadmapTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (_focusTopic != null && _roadmapRemainingSeconds > 0) {
        setState(() {}); 
        _startRoadmapTimerLoop();
      }
    }
  }

  Future<void> _restoreRoadmapState() async {
    final prefs = await SharedPreferences.getInstance();
    String topicKey = 'roadmap_focus_topic_${widget.notebookId}';
    String remainingKey = 'roadmap_remaining_seconds_${widget.notebookId}'; 

    String? savedTopic = prefs.getString(topicKey);
    int? savedRemaining = prefs.getInt(remainingKey);

    if (savedTopic != null && savedRemaining != null && savedRemaining > 0) {
      setState(() {
        _focusTopic = savedTopic;
        _roadmapRemainingSeconds = savedRemaining; 
      });
      _startRoadmapTimerLoop(); 
    } else {
      _clearRoadmapStorage();
    }
  }

  void _startRoadmapTimerLoop() {
    _roadmapTimer?.cancel(); 
    _roadmapTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_roadmapRemainingSeconds > 0) {
          _roadmapRemainingSeconds--;
          SharedPreferences.getInstance().then((prefs) {
            prefs.setInt('roadmap_remaining_seconds_${widget.notebookId}', _roadmapRemainingSeconds);
          });
        } else {
          timer.cancel();
          _focusTopic = null;
          _roadmapRemainingSeconds = 0;
          _clearRoadmapStorage();

          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("🎉 Hết thời gian Giai đoạn này! Đã mở khóa full tài liệu."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ));
        }
      });
    });
  }

  Future<void> _clearRoadmapStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('roadmap_focus_topic_${widget.notebookId}');
    await prefs.remove('roadmap_remaining_seconds_${widget.notebookId}');
  }

  Future<void> _toggleAudio(String text) async {
    if (_currentlyPlayingText == text && _audioPlayer.state == PlayerState.playing) {
      await _audioPlayer.stop();
      setState(() { _currentlyPlayingText = null; });
      return; 
    }
    if (_audioPlayer.state == PlayerState.playing) {
      await _audioPlayer.stop();
    }
    setState(() { _currentlyPlayingText = text; });

    String cleanText = text.replaceAll(RegExp(r'[*#_`]'), ''); 
    String ttsUrl = "${ApiConstants.baseUrl}/api/tts?text=${Uri.encodeComponent(cleanText)}";
    await _audioPlayer.play(UrlSource(ttsUrl));
  }

  Future<void> _quickSaveNote(String content) async {
    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/notes"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": _username, 
          "notebook_id": widget.notebookId, 
          "title": "Kiến thức từ AI", 
          "content": content
        }),
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
    _fetchChatHistory();  
    _restoreRoadmapState(); 
  }

  Future<void> _fetchChatHistory() async {
    setState(() => _isChatLoading = true);
    try {
      final response = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/chat_history/$_username/${widget.notebookId}"));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes))['data'] as List;
        setState(() {
          _messages.clear(); 
          if (data.isEmpty) {
            _messages.add({"sender": "ai", "text": "Xin chào! Mình là AI Companion. Bạn hãy tải tài liệu lên và hỏi mình bất cứ điều gì nhé!"});
          } else {
            for (var item in data) {
              _messages.add({"sender": item['sender'], "text": item['message']});
            }
            _scrollToBottom();
          }
        });
      }
    } catch (e) { print("Lỗi tải lịch sử chat: $e"); }
    setState(() => _isChatLoading = false);
  }

  Future<void> _fetchDashboardStats() async {
    try {
      final response = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/dashboard/$_username"));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (mounted) setState(() => _streak = data['streak'] ?? 0);
      }
    } catch (e) { print("Lỗi tải streak: $e"); }

    try {
      final notifResponse = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/notifications/$_username/${widget.notebookId}"));
      if (notifResponse.statusCode == 200) {
        final notifData = jsonDecode(utf8.decode(notifResponse.bodyBytes));
        if (mounted) {
          setState(() {
            _notifications = notifData['notifications'] ?? [];
            _unreadCount = notifData['unread_count'] ?? 0;
          });
        }
      }
    } catch (e) { print("Lỗi tải thông báo: $e"); }
  }

  void _openNotifications() {
    setState(() => _unreadCount = 0); 
    
    http.put(Uri.parse("${ApiConstants.baseUrl}/api/notifications/read_all/$_username/${widget.notebookId}"))
        .catchError((e) => print("Lỗi đánh dấu đọc: $e"));

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

                    bool isRead = n['is_read'] ?? true;

                    return Card(
                      elevation: isRead ? 0 : 2,
                      color: isRead ? Colors.white : Colors.blue.shade50,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isRead ? Colors.grey.shade200 : Colors.blue.shade200)
                      ),
                      child: ListTile(
                        onTap: () async {
                          Navigator.pop(context);
                          String msg = n['message'].toString();
                          if (msg.contains("Flashcard") || msg.contains("thẻ")) {
                            _roadmapTimer?.cancel(); 
                            await Navigator.push(context, MaterialPageRoute(builder: (context) => FlashcardScreen(username: _username, notebookId: widget.notebookId, isReviewMode: true)));
                            
                            if (_focusTopic != null) {
                              setState(() {}); 
                              _startRoadmapTimerLoop(); 
                            }
                            _fetchDashboardStats();
                          }
                        },
                        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
                        title: Text(
                          n['title'] ?? "Thông báo", 
                          style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold, fontSize: 15)
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(n['message'], style: TextStyle(fontSize: 13, color: isRead ? Colors.grey.shade700 : Colors.black87)),
                            const SizedBox(height: 4),
                            Text(n['time'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _fetchDashboardStats(); 
            }, 
            child: const Text("Đóng", style: TextStyle(fontSize: 16))
          ),
        ],
      ),
    );
  }

  Future<void> _fetchFiles() async {
    setState(() => _isFilesLoading = true);
    try {
      final response = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/files/$_username/${widget.notebookId}"));
      if (response.statusCode == 200) {
        setState(() => _uploadedFiles = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) { print(e); }
    setState(() => _isFilesLoading = false);
  }

  Future<void> _deleteFile(int fileId) async {
    try {
      final response = await http.delete(Uri.parse("${ApiConstants.baseUrl}/api/files/$fileId"));
      if (response.statusCode == 200) {
        _fetchFiles(); 
        if (!mounted) return; 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa tài liệu khỏi danh sách!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.grey));
      }
    } catch (e) { print(e); }
  }

  Future<void> _uploadPDF() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom, 
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'txt', 'jpg', 'jpeg', 'png'], 
      withData: true
    );
    if (result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang gửi file cho AI học...')));

    try {
      final request = http.MultipartRequest('POST', Uri.parse('${ApiConstants.baseUrl}/api/upload'));
      request.fields['user_id'] = _username;
      request.fields['notebook_id'] = widget.notebookId;
      
      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes('file', result.files.single.bytes!, filename: result.files.single.name));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', result.files.single.path!));
      }
      
      final response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        _fetchFiles(); 
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ AI đã học xong tài liệu!'), backgroundColor: Colors.green));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi máy chủ: $respStr'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)));
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
      var request = http.Request('POST', Uri.parse("${ApiConstants.baseUrl}/api/chat"));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        "user_id": _username, 
        "notebook_id": widget.notebookId, 
        "message": text,
        "focus_topic": _focusTopic 
      });

      var response = await http.Client().send(request);

      if (response.statusCode == 200) {
        setState(() {
          _messages.removeLast(); 
          _messages.add({"sender": "ai", "text": ""}); 
        });

        await for (var chunk in response.stream.transform(utf8.decoder)) {
          setState(() {
            _messages.last["text"] = _messages.last["text"]! + chunk;
          });
          _scrollToBottom(); 
        }
      } else {
        setState(() {
          _messages.removeLast();
          _messages.add({"sender": "ai", "text": "Hệ thống bận hoặc lỗi kết nối!"});
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

  String _cleanAndFormatTheory(String rawText) {
    String result = rawText.replaceAll("Dữ liệu JSON", "");
    result = result.replaceAll(RegExp(r'Định dạng lại bằng Markdown', caseSensitive: false), ""); 
    result = result.replaceAll(RegExp(r'VĂN BẢN THÔ', caseSensitive: false), ""); 

    final RegExp jsonRegExp = RegExp(r'\{[\s\S]*?\}');
    result = result.replaceAllMapped(jsonRegExp, (match) {
      String jsonString = match.group(0) ?? "";
      try {
        Map<String, dynamic> jsonData = jsonDecode(jsonString);
        String beautifulText = "\n";
        jsonData.forEach((key, value) {
          String prettyKey = key.replaceAll('_', ' ');
          if (prettyKey.isNotEmpty) {
            prettyKey = prettyKey[0].toUpperCase() + prettyKey.substring(1);
          }
          beautifulText += "🔹 **$prettyKey**: $value\n\n";
        });
        return beautifulText;
      } catch (e) { return "```text\n$jsonString\n```"; }
    });
    return result.trim();
  }

  Future<void> _showReferenceTheory(String filename, int page) async {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.indigo)),
    );

    try {
      final response = await http.get(
        Uri.parse("${ApiConstants.baseUrl}/api/reference?user_id=$_username&filename=$filename&page=$page&notebook_id=${widget.notebookId}"),
      );
      if (!mounted) return;
      Navigator.pop(context); 

      String theoryContent = "Lỗi không tải được dữ liệu.";
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        theoryContent = _cleanAndFormatTheory(data['data']); 
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: const Color(0xFFFAFAFA),
          title: Row(
            children: [
              const Icon(Icons.menu_book, color: Colors.indigo),
              const SizedBox(width: 10),
              Expanded(child: Text("$filename - Trang $page", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo), overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)]),
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: theoryContent,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                    tableBorder: TableBorder.all(color: Colors.grey.shade300, width: 1),
                    tableCellsPadding: const EdgeInsets.all(8),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text("Đã hiểu", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi kết nối máy chủ!")));
    }
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
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Row(
        children: [
          const Icon(Icons.auto_stories, color: Colors.indigo, size: 30),
          const SizedBox(width: 15),
          const Text("AI STUDY COMPANION", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
          const Spacer(),
          
          _buildBadge(Icons.local_fire_department, "$_streak ngày", _streak > 0 ? Colors.orange : Colors.grey),
          const SizedBox(width: 15),

          if (_focusTopic != null && _roadmapRemainingSeconds > 0)
            _buildBadge(Icons.timer, _formatTime(_roadmapRemainingSeconds), Colors.redAccent),
          
          const SizedBox(width: 15),
          
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(icon: const Icon(Icons.notifications_none_rounded, color: Colors.grey, size: 28), onPressed: _openNotifications),
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

          PopupMenuButton<String>(
            offset: const Offset(0, 45), 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            tooltip: 'Tùy chọn tài khoản',
            onSelected: (value) async {
              if (value == 'logout') {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('username');
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const AuthScreen()), (route) => false);
              }
            },
            child: Row(
              children: [
                Text(_username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(width: 10),
                const CircleAvatar(radius: 18, backgroundColor: Colors.blueAccent, child: Icon(Icons.person, color: Colors.white, size: 20)),
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

  String _formatMarkdownLink(String text) {
    return text.replaceAllMapped(RegExp(r'\(http://ref/([^)]+)\)'), (match) {
      String rawPath = match.group(1) ?? '';
      return '(http://ref/${Uri.encodeComponent(rawPath)})';
    });
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5DBB93), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
                      decoration: BoxDecoration(color: isAi ? Colors.white : const Color(0xFF6C63FF), borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)]),
                      child: isAi 
                        ? Builder(
                            builder: (context) {
                              String rawText = m['text']!;
                              String displayText = rawText;
                              List<dynamic> sourceMap = [];

                              if (rawText.contains("|||METADATA|||")) {
                                var parts = rawText.split("|||METADATA|||");
                                displayText = parts[0]; 
                                try { sourceMap = jsonDecode(parts[1]); } catch (e) { print(e); }
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MarkdownBody(
                                    data: _formatMarkdownLink(displayText),
                                    styleSheet: MarkdownStyleSheet(
                                      p: const TextStyle(fontSize: 15, color: Colors.black87),
                                      a: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                    ),
                                    onTapLink: (text, href, title) {
                                      if (href != null && href.startsWith('http://ref/')) {
                                        String cleanHref = Uri.decodeComponent(href.replaceAll('http://ref/', '').trim());
                                        final parts = cleanHref.split('|');
                                        if (parts.length >= 2) {
                                          _showReferenceTheory(parts[0].trim(), int.tryParse(parts[1].trim()) ?? 1);
                                        }
                                      }
                                    },
                                  ),
                                  if (sourceMap.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    const Text("📍 Nguồn tài liệu:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: sourceMap.map((src) {
                                        return ActionChip(
                                          avatar: CircleAvatar(backgroundColor: Colors.indigo.shade100, child: Text("${src['id']}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo))),
                                          label: Text("${src['file']} (Tr. ${src['page']})", style: const TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.indigo.withOpacity(0.05),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          onPressed: () { _showReferenceTheory(src['file'], int.tryParse(src['page'].toString()) ?? 1); },
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                  if (m['text'] != "Đang suy nghĩ...") ...[
                                    const SizedBox(height: 10),
                                    const Divider(color: Colors.black12, height: 1),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(icon: const Icon(Icons.volume_up, size: 20, color: Colors.orange), onPressed: () => _toggleAudio(displayText)),
                                        IconButton(icon: const Icon(Icons.bookmark_add_outlined, size: 20, color: Colors.teal), onPressed: () => _quickSaveNote(displayText)),
                                      ],
                                    )
                                  ]
                                ],
                              );
                            }
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
                  decoration: InputDecoration(hintText: "Hỏi AI về bài học...", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 20)),
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(backgroundColor: const Color(0xFF6C63FF), child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendChatMessage)),
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
          _buildActionItem("Lộ trình học AI", Icons.map, const Color(0xFFFFF3E0), Colors.deepOrange, () async {
             _roadmapTimer?.cancel(); 
             final selectedStage = await Navigator.push(context, MaterialPageRoute(builder: (context) => RoadmapScreen(username: _username, notebookId: widget.notebookId)));
             
             if (selectedStage != null) {
               String title = selectedStage['title'];
               String timeStr = selectedStage['estimated_time'].toString();
               List<dynamic> tasks = selectedStage['tasks'] ?? [];
               
               int minutes = int.tryParse(timeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 30;
               
               final prefs = await SharedPreferences.getInstance();
               await prefs.setString('roadmap_focus_topic_${widget.notebookId}', title);
               await prefs.setInt('roadmap_remaining_seconds_${widget.notebookId}', minutes * 60);

               setState(() {
                 _focusTopic = title; 
                 _roadmapRemainingSeconds = minutes * 60; 
               });

               _startRoadmapTimerLoop(); 

               String taskList = tasks.join(", "); 
               _chatController.text = "Hãy làm gia sư dạy tôi chủ đề: $title. Bắt đầu bằng việc hướng dẫn tôi thực hiện các nhiệm vụ sau: $taskList";
               _sendChatMessage();
             } else {
               if (_focusTopic != null) {
                 setState(() {}); 
                 _startRoadmapTimerLoop();
               }
             }
          }),
          
          _buildActionItem("Tạo Quiz", Icons.settings_suggest, const Color(0xFFE3F9F1), Colors.teal, () { 
            _showQuizSettingsDialog(); 
          }),
          
          _buildActionItem("Phòng thi ảo", Icons.timer, const Color(0xFFEBF3FF), Colors.blueAccent, () async {
             _roadmapTimer?.cancel(); 
             await Navigator.push(context, MaterialPageRoute(builder: (context) => QuizScreen(
               modeName: "Phòng thi ảo", 
               numQuestions: 30, 
               timeLimit: 2400, 
               username: _username, 
               difficulty: "Phòng thi ảo", 
               notebookId: widget.notebookId,
               focusTopic: null, 
             )));
             
             if (_focusTopic != null) {
               setState(() {}); 
               _startRoadmapTimerLoop(); 
             }
             _fetchDashboardStats(); 
          }),
          
          _buildActionItem("Flashcards", Icons.style, const Color(0xFFF3EFFF), Colors.purple, () async {
             _roadmapTimer?.cancel(); 
             await Navigator.push(context, MaterialPageRoute(builder: (context) => FlashcardScreen(
               username: _username, 
               notebookId: widget.notebookId,
               focusTopic: _focusTopic, 
             )));
             
             if (_focusTopic != null) {
               setState(() {}); 
               _startRoadmapTimerLoop(); 
             }
          }),
          
          _buildActionItem("Sổ tay ghi nhớ", Icons.book, const Color(0xFFE8F5E9), Colors.green, () async {
             _roadmapTimer?.cancel(); 
             await Navigator.push(context, MaterialPageRoute(builder: (context) => NoteScreen(username: _username, notebookId: widget.notebookId)));
             
             if (_focusTopic != null) {
               setState(() {}); 
               _startRoadmapTimerLoop(); 
             }
          }),
          
          _buildActionItem("Lịch sử Quiz và Flashcard", Icons.emoji_events, const Color(0xFFFFF8E1), Colors.orange, () async {
             _roadmapTimer?.cancel(); 
             await Navigator.push(context, MaterialPageRoute(builder: (context) => StudyHistoryScreen(username: _username, notebookId: widget.notebookId)));
             
             if (_focusTopic != null) {
               setState(() {}); 
               _startRoadmapTimerLoop(); 
             }
          }),  
          
          _buildActionItem("Sơ đồ tư duy AI", Icons.account_tree, const Color(0xFFFCE4EC), Colors.pink, () async {
             _roadmapTimer?.cancel(); 
             final selectedConcept = await Navigator.push(context, MaterialPageRoute(builder: (context) => ConceptMapScreen(username: _username, notebookId: widget.notebookId)));
             
             if (_focusTopic != null) {
               setState(() {}); 
               _startRoadmapTimerLoop(); 
             }

             if (selectedConcept != null && selectedConcept is String) {
               _chatController.text = "Hãy giải thích chi tiết và dễ hiểu cho tôi về khái niệm: $selectedConcept";
               _sendChatMessage();
             }
          }),
        ],
      ),
    );
  }

  Widget _buildPanelContainer({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 15), Expanded(child: child)]),
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
          Expanded(child: Tooltip(message: name, child: Text(name, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis))),
          IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 18), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _deleteFile(id)),
        ],
      ),
    );
  }

  Widget _buildActionItem(String label, IconData icon, Color bg, Color iconCol, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(onTap: onTap, tileColor: bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), leading: Icon(icon, color: iconCol), title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), trailing: const Icon(Icons.chevron_right, size: 18)),
    );
  }

  Widget _buildBadge(IconData icon, String text, Color col) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: col.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [Icon(icon, color: col, size: 18), const SizedBox(width: 5), Text(text, style: TextStyle(color: col, fontWeight: FontWeight.bold))]),
    );
  }

  Future<void> _showQuizSettingsDialog() async {
    int selectedNum = 5;
    String selectedDiff = "Trung bình";
    String selectedType = "Trộn lẫn";

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(children: [Icon(Icons.tune, color: Colors.teal), SizedBox(width: 10), Text("Tùy chỉnh Bộ đề", style: TextStyle(fontWeight: FontWeight.bold))]),
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
                  const SizedBox(height: 15),
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
                  const SizedBox(height: 15),
                  const Text("Loại câu hỏi:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedType,
                        isExpanded: true,
                        items: ["Trộn lẫn", "Trắc nghiệm", "Đúng/Sai", "Điền khuyết", "Trả lời ngắn"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (val) => setDialogState(() => selectedType = val!),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy bỏ", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context); 
                    
                    _roadmapTimer?.cancel(); 
                    await Navigator.push(context, MaterialPageRoute(builder: (context) => QuizScreen(
                      modeName: "Quiz ($selectedDiff)", 
                      numQuestions: selectedNum, 
                      timeLimit: 0, 
                      username: _username, 
                      difficulty: selectedDiff, 
                      notebookId: widget.notebookId, 
                      quizType: selectedType,
                      focusTopic: _focusTopic, 
                    )));
                    
                    if (_focusTopic != null) {
                      setState(() {}); 
                      _startRoadmapTimerLoop(); 
                    }
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