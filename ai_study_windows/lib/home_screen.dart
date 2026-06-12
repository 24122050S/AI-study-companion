import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:audioplayers/audioplayers.dart';

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

// ── Bảng màu mới — lấy cảm hứng từ hình nền Space Adventure ──────────────
// Teal mint (sóng, mây, vòng Saturn) · Hot pink (doodles) · Deep purple (bút, hành tinh)
const Color cPink     = Color(0xFFEA5D8B); // Hot pink — outline doodles
const Color cPinkDeep = Color(0xFFD63875); // Deep pink — CTA buttons
const Color cBlue     = Color(0xFF5C3F99); // Deep purple — pencil / planet
const Color cBlueSoft = Color(0xFF9B7DD4); // Soft purple — secondary
const Color cLeaf     = Color(0xFF3DC9B0); // Teal mint — waves / clouds
const Color cBg       = Color(0xFFF0FDFB); // Very light teal bg
const Color cCard     = Color(0xFFFFFFFF); // White card
const Color cText     = Color(0xFF2C2541); // Dark purple-gray text
const Color cMuted    = Color(0xFF8080A0); // Muted blue-gray
const Color cBorder   = Color(0xFFCCEFEB); // Teal border
const Color cSurface  = Color(0xFFF0FDFB); // Light teal surface
const Color cYellow   = Color(0xFFFFCC5C); // Yellow — streak badge

String? _focusTopic;
Timer? _roadmapTimer;
int _roadmapRemainingSeconds = 0;

String _formatTime(int seconds) {
  int m = seconds ~/ 60;
  int s = seconds % 60;
  return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
}

class HomeScreen extends StatefulWidget {
  final String notebookId;
  final String notebookTitle;
  const HomeScreen({super.key, required this.notebookId, required this.notebookTitle});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isChatLoading = false;
  List<dynamic> _uploadedFiles = [];
  bool _isFilesLoading = false;
  bool _isFilesExpanded = true;
  bool _isToolsExpanded = true;
  bool _isUploading = false;
  int _streak = 0;
  List<dynamic> _notifications = [];
  int _unreadCount = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingText;
  String _username = "An Nguyen";

  late AnimationController _entranceAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entranceAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
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
    _entranceAnim.dispose();
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
          _toast("🎉 Hết thời gian Giai đoạn này! Đã mở khóa full tài liệu.", cLeaf);
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
      final r = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/notes"), // Đã sửa lại đường dẫn chuẩn
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": _username, 
          "notebook_id": widget.notebookId, 
          "title": "Kiến thức AI", 
          "content": content
        }),
      );
      if (r.statusCode == 200 && mounted) _toast("✅ Đã lưu vào Sổ tay!", cLeaf);
    } catch (_) {}
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _username = prefs.getString('username') ?? "An Nguyen");
    _fetchFiles();
    _fetchDashboardStats();
    _fetchChatHistory();
    _restoreRoadmapState();
  }

  Future<void> _fetchChatHistory() async {
    setState(() => _isChatLoading = true);
    try {
      final r = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/chat_history/$_username/${widget.notebookId}"));
      if (r.statusCode == 200) {
        final data = jsonDecode(utf8.decode(r.bodyBytes))['data'] as List;
        setState(() {
          _messages.clear();
          if (data.isEmpty) {
            _messages.add({"sender": "ai", "text": "Xin chào! Mình là AI Companion 🤖.\nHãy đính kèm tài liệu và hỏi mình bất cứ điều gì nhé!"});
          } else {
            for (var item in data) _messages.add({"sender": item['sender'], "text": item['message']});
            _scrollToBottom();
          }
        });
      }
    } catch (_) {}
    setState(() => _isChatLoading = false);
  }

  Future<void> _fetchDashboardStats() async {
    try {
      final r = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/dashboard/$_username"));
      if (r.statusCode == 200 && mounted) {
        setState(() => _streak = jsonDecode(utf8.decode(r.bodyBytes))['streak'] ?? 0);
      }
    } catch (_) {}

    try {
      final notifResponse = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/notifications/$_username/${widget.notebookId}"));
      if (notifResponse.statusCode == 200 && mounted) {
        final notifData = jsonDecode(utf8.decode(notifResponse.bodyBytes));
        setState(() {
          _notifications = notifData['notifications'] ?? [];
          _unreadCount = notifData['unread_count'] ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchFiles() async {
    setState(() => _isFilesLoading = true);
    try {
      final r = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/files/$_username/${widget.notebookId}"));
      if (r.statusCode == 200 && mounted) setState(() => _uploadedFiles = jsonDecode(utf8.decode(r.bodyBytes)));
    } catch (_) {}
    setState(() => _isFilesLoading = false);
  }

  Future<void> _deleteFile(int id) async {
    try {
      final r = await http.delete(Uri.parse("${ApiConstants.baseUrl}/api/files/$id"));
      if (r.statusCode == 200) { _fetchFiles(); _toast("Đã xóa tài liệu!", cPinkDeep); }
    } catch (_) {}
  }

  Future<void> _uploadPDF() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'txt', 'jpg', 'jpeg', 'png'],
      withData: true
    );
    if (result == null) return;
    setState(() => _isUploading = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse('${ApiConstants.baseUrl}/api/upload'));
      request.fields['user_id'] = _username;
      request.fields['notebook_id'] = widget.notebookId;
      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes('file', result.files.single.bytes!, filename: result.files.single.name));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', result.files.single.path!));
      }
      final resp = await request.send();
      if (resp.statusCode == 200) { await _fetchFiles(); _toast("✅ AI đã học xong tài liệu!", cLeaf); }
    } catch (_) {}
    setState(() => _isUploading = false);
  }

  Future<void> _sendChatMessage() async {
    String text = _chatController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add({"sender": "user", "text": text});
      _messages.add({"sender": "ai", "text": "Đang phân tích..."});
      _isChatLoading = true;
      _chatController.clear();
    });
    _scrollToBottom();
    try {
      var req = http.Request('POST', Uri.parse("${ApiConstants.baseUrl}/api/chat"));
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode({
        "user_id": _username,
        "notebook_id": widget.notebookId,
        "message": text,
        "focus_topic": _focusTopic
      });
      var response = await http.Client().send(req);
      if (response.statusCode == 200) {
        setState(() { _messages.removeLast(); _messages.add({"sender": "ai", "text": ""}); });
        await for (var chunk in response.stream.transform(utf8.decoder)) {
          setState(() => _messages.last["text"] = _messages.last["text"]! + chunk);
          _scrollToBottom();
        }
      } else {
        setState(() { _messages.removeLast(); _messages.add({"sender": "ai", "text": "Hệ thống bận hoặc lỗi kết nối!"}); });
      }
    } catch (_) {
      setState(() { _messages.removeLast(); _messages.add({"sender": "ai", "text": "Lỗi kết nối máy chủ."}); });
    } finally {
      setState(() => _isChatLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _toast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: color, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(20),
    ));
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
      builder: (context) => const Center(child: CircularProgressIndicator(color: cPinkDeep)),
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
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cLeaf, width: 2),
              boxShadow: [BoxShadow(color: cLeaf.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_rounded, color: cLeaf, size: 24),
                    const SizedBox(width: 10),
                    Expanded(child: Text("$filename - Trang $page", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cText), overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 350,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cBorder)),
                  child: SingleChildScrollView(
                    child: MarkdownBody(
                      data: theoryContent,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 14.5, height: 1.6, color: cText),
                        tableBorder: TableBorder.all(color: cBorder, width: 1),
                        tableCellsPadding: const EdgeInsets.all(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cPinkDeep, elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Đã hiểu", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _toast("Lỗi kết nối máy chủ!", cPinkDeep);
    }
  }

  void _openNotifications() {
    setState(() => _unreadCount = 0);
    http.put(Uri.parse("${ApiConstants.baseUrl}/api/notifications/read_all/$_username/${widget.notebookId}"));

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 440, padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: cCard, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cLeaf, width: 2),
            boxShadow: [BoxShadow(color: cLeaf.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.notifications_rounded, color: cLeaf, size: 22),
              const SizedBox(width: 10),
              const Text("THÔNG BÁO", style: TextStyle(color: cText, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              height: 350,
              child: _notifications.isEmpty
                  ? Center(child: Text("Không có thông báo mới.", style: TextStyle(color: cMuted)))
                  : ListView.builder(
                      shrinkWrap: true, itemCount: _notifications.length,
                      itemBuilder: (_, i) {
                        final n = _notifications[i];
                        IconData icon; Color color;
                        if (n['type'] == 'success') { icon = Icons.stars; color = cLeaf; }
                        else if (n['type'] == 'danger') { icon = Icons.warning_rounded; color = cPinkDeep; }
                        else if (n['type'] == 'warning') { icon = Icons.flag; color = const Color(0xFFE8A838); }
                        else { icon = Icons.info; color = cBlue; }
                        
                        bool isRead = n['is_read'] ?? true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: isRead ? cCard : cPink.withOpacity(0.05), 
                            borderRadius: BorderRadius.circular(12), 
                            border: Border.all(color: isRead ? cBorder : cPink)
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
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                              child: Icon(icon, color: color, size: 18),
                            ),
                            title: Text(n['title'] ?? "Thông báo", style: TextStyle(color: cText, fontWeight: isRead ? FontWeight.w600 : FontWeight.w800, fontSize: 14)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(n['message'], style: TextStyle(color: isRead ? cMuted : cText, fontSize: 13)),
                                const SizedBox(height: 6),
                                Text(n['time'], style: TextStyle(color: cMuted.withOpacity(0.6), fontSize: 11)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _fetchDashboardStats();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: cPinkDeep, elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Đóng", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/home_screen.jpg'),
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCCFFFFFF),  // Trắng trong vắt phía trên (bầu trời)
                Color(0x99F5FFFD),  // Teal rất nhẹ ở giữa
                Color(0xBBE5FAF7),  // Teal nhạt phủ sóng phía dưới
              ],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _entranceAnim, curve: Curves.easeOut),
              child: Row(
                children: [
                  _buildSidebar(),
                  Expanded(
                    child: Column(
                      children: [
                        _buildHeader(),
                        _buildToolsRow(),
                        Expanded(
                          child: Center(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 820),
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                                itemCount: _messages.length,
                                itemBuilder: (_, i) {
                                  final m = _messages[i];
                                  final isAi = m['sender'] == 'ai';
                                  String rawText = m['text']!;
                                  String displayText = rawText;
                                  List<dynamic> sourceMap = [];

                                  if (rawText.contains("|||METADATA|||")) {
                                    var parts = rawText.split("|||METADATA|||");
                                    displayText = parts[0];
                                    try { sourceMap = jsonDecode(parts[1]); } catch (e) {}
                                  }

                                  return _ChatBubble(
                                    message: displayText,
                                    isAi: isAi,
                                    sourceMap: sourceMap,
                                    onSpeak: isAi && displayText != "Đang phân tích..." ? () => _toggleAudio(displayText) : null,
                                    onSave: isAi && displayText != "Đang phân tích..." ? () => _quickSaveNote(displayText) : null,
                                    onReferenceClick: (filename, page) => _showReferenceTheory(filename, page),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        _buildFloatingInput(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isFilesExpanded ? 272 : 0,
      child: !_isFilesExpanded ? const SizedBox() : Container(
        decoration: BoxDecoration(
          color: cCard.withOpacity(0.92),
          border: Border(right: BorderSide(color: cBorder, width: 1.5)),
          boxShadow: [BoxShadow(color: cLeaf.withOpacity(0.15), blurRadius: 20, offset: const Offset(4, 0))],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 8, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: cBorder)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: cLeaf.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.picture_as_pdf_rounded, color: cLeaf, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text("Tài liệu Học liệu", style: TextStyle(color: cText, fontWeight: FontWeight.w800, fontSize: 14)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: cMuted, size: 20),
                    onPressed: () => setState(() => _isFilesExpanded = false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isFilesLoading
                  ? Center(child: CircularProgressIndicator(color: cPink, strokeWidth: 2))
                  : _uploadedFiles.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.folder_open_rounded, color: cMuted.withOpacity(0.4), size: 48),
                            const SizedBox(height: 10),
                            Text("Chưa có tài liệu", style: TextStyle(color: cMuted, fontSize: 13)),
                          ]),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: _uploadedFiles.length,
                          itemBuilder: (_, i) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: cSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cBorder),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              leading: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: cLeaf.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.description_rounded, color: cLeaf, size: 16),
                              ),
                              title: Tooltip(
                                message: _uploadedFiles[i]['filename'],
                                child: Text(_uploadedFiles[i]['filename'],
                                    style: const TextStyle(color: cText, fontSize: 12, fontWeight: FontWeight.w600),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: cMuted, size: 16),
                                onPressed: () => _deleteFile(_uploadedFiles[i]['id']),
                              ),
                            ),
                          ),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _isUploading
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: cPink, strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text("Đang tải & học...", style: TextStyle(color: cMuted, fontSize: 13)),
                    ])
                  : ElevatedButton.icon(
                      onPressed: _uploadPDF,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text("Tải File Lên", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cLeaf, foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: cCard.withOpacity(0.88),
        border: Border(bottom: BorderSide(color: cBorder, width: 1.5)),
        boxShadow: [BoxShadow(color: cLeaf.withOpacity(0.10), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          if (!_isFilesExpanded)
            _HeaderIconBtn(
              icon: Icons.menu_rounded,
              color: cBlue,
              onTap: () => setState(() => _isFilesExpanded = true),
            ),
          _HeaderIconBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            color: cMuted,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: cLeaf.withOpacity(0.18), borderRadius: BorderRadius.circular(9)),
            child: Icon(Icons.menu_book_rounded, color: cLeaf, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.notebookTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cText),
                overflow: TextOverflow.ellipsis),
          ),
          _CollapseToggleButton(
            isExpanded: _isToolsExpanded,
            onTap: () => setState(() => _isToolsExpanded = !_isToolsExpanded),
          ),
          const SizedBox(width: 16),
          if (_focusTopic != null && _roadmapRemainingSeconds > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cPinkDeep.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cPinkDeep.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer_outlined, size: 14, color: cPinkDeep),
                const SizedBox(width: 5),
                Text(_formatTime(_roadmapRemainingSeconds), style: const TextStyle(color: cPinkDeep, fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 12),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cYellow.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cYellow.withOpacity(0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text("🔥", style: TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text("$_streak ngày", style: const TextStyle(color: cText, fontWeight: FontWeight.bold, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 12),
          Stack(clipBehavior: Clip.none, children: [
            _HeaderIconBtn(icon: Icons.notifications_rounded, color: cBlue, onTap: _openNotifications),
            if (_unreadCount > 0)
              Positioned(
                right: 4, top: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: cPinkDeep, shape: BoxShape.circle),
                  child: Text('$_unreadCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            offset: const Offset(0, 46),
            color: cCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cBorder)),
            onSelected: (v) async {
              if (v == 'logout') {
                final p = await SharedPreferences.getInstance();
                await p.remove('username');
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
              }
            },
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [cLeaf, cBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: cLeaf.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Center(child: Text(
                _username.isNotEmpty ? _username[0].toUpperCase() : "?",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
              )),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'logout', child: Row(children: [
                Icon(Icons.logout_rounded, color: cPinkDeep, size: 18),
                SizedBox(width: 10),
                Text("Đăng xuất", style: TextStyle(color: cPinkDeep, fontWeight: FontWeight.bold)),
              ])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolsRow() {
    final tools = [
      _ToolItem(icon: Icons.map_rounded, label: "Lộ trình AI", color: cLeaf, onTap: () async {
        _roadmapTimer?.cancel();
        final selectedStage = await Navigator.push(context, MaterialPageRoute(builder: (context) => RoadmapScreen(username: _username, notebookId: widget.notebookId)));
        if (selectedStage != null) {
          String title = selectedStage['title'];
          String timeStr = selectedStage['estimated_time'].toString();
          List<dynamic> tasks = selectedStage['tasks'] ?? [];
          int minutes = int.tryParse(timeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 30;
          
          String taskList = tasks.join(", ");
          // 🚀 ĐÃ SỬA: Ép cả tên Chủ đề + Giới hạn nhiệm vụ (trang) vào Focus Topic
          String detailedTopic = "$title (Phạm vi bắt buộc: $taskList)";
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('roadmap_focus_topic_${widget.notebookId}', detailedTopic);
          await prefs.setInt('roadmap_remaining_seconds_${widget.notebookId}', minutes * 60);

          setState(() {
            _focusTopic = detailedTopic;
            _roadmapRemainingSeconds = minutes * 60;
          });
          _startRoadmapTimerLoop();
          
          _chatController.text = "Hãy làm gia sư dạy tôi chủ đề: $title. Bắt đầu bằng việc hướng dẫn tôi thực hiện các nhiệm vụ sau: $taskList";
          _sendChatMessage();
        } else if (_focusTopic != null) {
          setState(() {});
          _startRoadmapTimerLoop();
        }
      }),
      _ToolItem(icon: Icons.quiz_rounded, label: "Tạo Quiz", color: cPinkDeep, onTap: _showQuizSettingsDialog),
      _ToolItem(icon: Icons.timer_rounded, label: "Phòng thi", color: const Color(0xFFE8A838), onTap: () async { 
        _roadmapTimer?.cancel();
        await Navigator.push(context, MaterialPageRoute(builder: (context) => QuizScreen(modeName: "Phòng thi ảo", numQuestions: 30, timeLimit: 2400, username: _username, difficulty: "Phòng thi ảo", notebookId: widget.notebookId, focusTopic: null))); 
        if (_focusTopic != null) { setState(() {}); _startRoadmapTimerLoop(); }
        _fetchDashboardStats(); 
      }),
      _ToolItem(icon: Icons.style_rounded, label: "Flashcard", color: cBlue, onTap: () async { 
        _roadmapTimer?.cancel();
        await Navigator.push(context, MaterialPageRoute(builder: (context) => FlashcardScreen(username: _username, notebookId: widget.notebookId, focusTopic: _focusTopic)));
        if (_focusTopic != null) { setState(() {}); _startRoadmapTimerLoop(); }
      }),
      _ToolItem(icon: Icons.edit_note_rounded, label: "Sổ tay", color: cBlueSoft, onTap: () async { 
        _roadmapTimer?.cancel();
        await Navigator.push(context, MaterialPageRoute(builder: (context) => NoteScreen(username: _username, notebookId: widget.notebookId)));
        if (_focusTopic != null) { setState(() {}); _startRoadmapTimerLoop(); }
      }),
      _ToolItem(icon: Icons.emoji_events_rounded, label: "Lịch sử", color: cPink, onTap: () async { 
        _roadmapTimer?.cancel();
        await Navigator.push(context, MaterialPageRoute(builder: (context) => StudyHistoryScreen(username: _username, notebookId: widget.notebookId)));
        if (_focusTopic != null) { setState(() {}); _startRoadmapTimerLoop(); }
      }),
      _ToolItem(icon: Icons.account_tree_rounded, label: "Sơ đồ tư duy", color: cBlueSoft, onTap: () async { 
        _roadmapTimer?.cancel();
        final selectedConcept = await Navigator.push(context, MaterialPageRoute(builder: (context) => ConceptMapScreen(username: _username, notebookId: widget.notebookId)));
        if (_focusTopic != null) { setState(() {}); _startRoadmapTimerLoop(); }
        if (selectedConcept != null && selectedConcept is String) {
          _chatController.text = "Hãy giải thích chi tiết và dễ hiểu cho tôi về khái niệm: $selectedConcept";
          _sendChatMessage();
        }
      }),
    ];

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _isToolsExpanded
          ? Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.35))),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: tools.map((t) => _ToolCard(item: t)).toList(),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildFloatingInput() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820),
        margin: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        decoration: BoxDecoration(
          color: cCard.withOpacity(0.95),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: cBorder, width: 1.5),
          boxShadow: [
            BoxShadow(color: cLeaf.withOpacity(0.18), blurRadius: 20, offset: const Offset(0, 6)),
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _isFilesExpanded = true),
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cLeaf.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.attach_file_rounded, color: cLeaf, size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _chatController,
              onSubmitted: (_) => _sendChatMessage(),
              style: const TextStyle(color: cText, fontSize: 15),
              decoration: InputDecoration(
                hintText: "Hỏi AI về kiến thức của bạn...",
                hintStyle: TextStyle(color: cMuted.withOpacity(0.7), fontSize: 15),
                border: InputBorder.none,
              ),
            ),
          ),
          GestureDetector(
            onTap: _sendChatMessage,
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [cLeaf, cPinkDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: cLeaf.withOpacity(0.40), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: _isChatLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _showQuizSettingsDialog() async {
    int selectedNum = 5;
    String selectedDiff = "Trung bình";
    String selectedType = "Trộn lẫn";

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 420, padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cCard, borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cLeaf, width: 2),
              boxShadow: [BoxShadow(color: cLeaf.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 10))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: cPinkDeep, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.quiz_rounded, color: Colors.white, size: 22)),
                const SizedBox(width: 14),
                const Text("Tạo bài Quiz AI", style: TextStyle(color: cText, fontSize: 20, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 24),
              Text("Số lượng câu hỏi:", style: TextStyle(color: cMuted, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: selectedNum, dropdownColor: cCard, style: const TextStyle(color: cText),
                decoration: InputDecoration(filled: true, fillColor: cSurface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                items: [5, 10, 15, 20, 30].map((e) => DropdownMenuItem(value: e, child: Text("$e câu"))).toList(),
                onChanged: (v) => set(() => selectedNum = v!),
              ),
              const SizedBox(height: 16),
              Text("Độ khó:", style: TextStyle(color: cMuted, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedDiff, dropdownColor: cCard, style: const TextStyle(color: cText),
                decoration: InputDecoration(filled: true, fillColor: cSurface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                items: ["Dễ", "Trung bình", "Khó"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => set(() => selectedDiff = v!),
              ),
              const SizedBox(height: 16),
              Text("Loại câu hỏi:", style: TextStyle(color: cMuted, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedType, dropdownColor: cCard, style: const TextStyle(color: cText),
                decoration: InputDecoration(filled: true, fillColor: cSurface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                items: ["Trộn lẫn", "Trắc nghiệm", "Đúng/Sai", "Điền khuyết", "Trả lời ngắn"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => set(() => selectedType = v!),
              ),
              const SizedBox(height: 28),
              Row(children: [
                Expanded(child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cBorder))),
                  child: Text("Hủy", style: TextStyle(color: cMuted, fontWeight: FontWeight.w700)),
                )),
                const SizedBox(width: 14),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: cPinkDeep, elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    _roadmapTimer?.cancel();
                    await Navigator.push(context, MaterialPageRoute(builder: (context) => QuizScreen(
                      modeName: "Quiz ($selectedDiff)", numQuestions: selectedNum, timeLimit: 0, 
                      username: _username, difficulty: selectedDiff, notebookId: widget.notebookId, 
                      quizType: selectedType, focusTopic: _focusTopic
                    )));
                    if (_focusTopic != null) { setState(() {}); _startRoadmapTimerLoop(); }
                    _fetchDashboardStats();
                  },
                  child: const Text("BẮT ĐẦU →", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ToolItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ToolItem({required this.icon, required this.label, required this.color, required this.onTap});
}

class _ToolCard extends StatefulWidget {
  final _ToolItem item;
  const _ToolCard({required this.item});
  @override State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.item.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          // ── Chiều rộng tối thiểu cố định để tất cả thẻ đều nhau ──
          constraints: const BoxConstraints(minWidth: 128),
          decoration: BoxDecoration(
            color: _hovered ? Color.fromARGB(255, (c.red * 0.82).round(), (c.green * 0.82).round(), (c.blue * 0.82).round()) : c,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: c.withOpacity(_hovered ? 0.45 : 0.25), blurRadius: _hovered ? 14 : 6, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center, // căn giữa khi rộng hơn nội dung
            children: [
              Icon(widget.item.icon, color: Colors.white, size: 17),
              const SizedBox(width: 7),
              Text(widget.item.label,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String message;
  final bool isAi;
  final List<dynamic>? sourceMap;
  final VoidCallback? onSpeak;
  final VoidCallback? onSave;
  final Function(String filename, int page)? onReferenceClick;

  const _ChatBubble({required this.message, required this.isAi, this.sourceMap, this.onSpeak, this.onSave, this.onReferenceClick});

  String _formatMarkdownLink(String text) {
    return text.replaceAllMapped(RegExp(r'\(http://ref/([^)]+)\)'), (match) {
      String rawPath = match.group(1) ?? '';
      return '(http://ref/${Uri.encodeComponent(rawPath)})';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.62),
        decoration: BoxDecoration(
          color: isAi ? cCard.withOpacity(0.95) : cPinkDeep,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isAi ? 4 : 20),
            bottomRight: Radius.circular(isAi ? 20 : 4),
          ),
          border: isAi ? Border.all(color: cBorder, width: 1.5) : null,
          boxShadow: [BoxShadow(
            color: isAi ? cPink.withOpacity(0.1) : cPinkDeep.withOpacity(0.25),
            blurRadius: 12, offset: const Offset(0, 4),
          )],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownBody(
                  data: _formatMarkdownLink(message),
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(fontSize: 14.5, height: 1.65, color: isAi ? cText : Colors.white),
                    code: TextStyle(backgroundColor: isAi ? cBorder : Colors.white24, color: isAi ? cPinkDeep : Colors.white, fontSize: 13),
                    codeblockDecoration: BoxDecoration(color: isAi ? cSurface : Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: isAi ? cBorder : Colors.transparent)),
                    a: TextStyle(color: isAi ? cBlue : Colors.white, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                  ),
                  onTapLink: (text, href, title) {
                    if (href != null && href.startsWith('http://ref/') && onReferenceClick != null) {
                      String cleanHref = Uri.decodeComponent(href.replaceAll('http://ref/', '').trim());
                      final parts = cleanHref.split('|');
                      if (parts.length >= 2) {
                        onReferenceClick!(parts[0].trim(), int.tryParse(parts[1].trim()) ?? 1);
                      }
                    }
                  },
                ),
                if (sourceMap != null && sourceMap!.isNotEmpty && isAi) ...[
                  const SizedBox(height: 12),
                  Text("📍 Nguồn tài liệu:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cMuted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: sourceMap!.map((src) {
                      return ActionChip(
                        avatar: CircleAvatar(backgroundColor: cLeaf.withOpacity(0.3), child: Text("${src['id']}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cLeaf))),
                        label: Text("${src['file']} (Tr. ${src['page']})", style: const TextStyle(fontSize: 12, color: cLeaf, fontWeight: FontWeight.w600)),
                        backgroundColor: cLeaf.withOpacity(0.08),
                        side: BorderSide(color: cLeaf.withOpacity(0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onPressed: () { if (onReferenceClick != null) onReferenceClick!(src['file'], int.tryParse(src['page'].toString()) ?? 1); },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          if (isAi && (onSpeak != null || onSave != null))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cSurface.withOpacity(0.8),
                borderRadius: const BorderRadius.only(bottomRight: Radius.circular(20), bottomLeft: Radius.circular(4)),
                border: Border(top: BorderSide(color: cBorder)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (onSpeak != null) IconButton(
                  icon: const Icon(Icons.volume_up_rounded, color: Color(0xFFE8A838), size: 18),
                  onPressed: onSpeak!, tooltip: "Đọc âm thanh",
                ),
                if (onSave != null) IconButton(
                  icon: const Icon(Icons.bookmark_add_rounded, color: cLeaf, size: 18),
                  onPressed: onSave!, tooltip: "Lưu sổ tay",
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _HeaderIconBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _CollapseToggleButton extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;
  const _CollapseToggleButton({required this.isExpanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isExpanded ? "Thu gọn công cụ" : "Mở rộng công cụ",
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: cBlue,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: cBlue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedRotation(
              turns: isExpanded ? 0 : 0.5,
              duration: const Duration(milliseconds: 300),
              child: const Icon(Icons.expand_less_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 4),
            Text(isExpanded ? "Ẩn" : "Công cụ",
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}