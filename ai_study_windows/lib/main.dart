import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart'; 
import 'package:google_fonts/google_fonts.dart';

import 'home_screen.dart';
import 'auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final String? loggedInUser = prefs.getString('username');

  runApp(MyApp(startScreen: loggedInUser != null ? const HomeScreen() : const AuthScreen()));
}

class MyApp extends StatelessWidget {
  final Widget startScreen;
  const MyApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gia sư AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC8E6C9)), // Màu xanh pastel nhẹ nhàng
        textTheme: GoogleFonts.nunitoTextTheme(), // Font hiện đại
        useMaterial3: true,
      ),
      // Dòng quan trọng để tránh lỗi trắng màn hình
      home: startScreen, 
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = []; 
  String _username = "Bạn"; 
  final String apiUrl = "http://127.0.0.1:8000"; 
  
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts(); 
    _loadUserAndGreet(); 
  }

  Future<void> _initTts() async {
    await Future.delayed(const Duration(milliseconds: 500));
    var isSuccess = await flutterTts.setLanguage("vi-VN");
    if (isSuccess == 0 || isSuccess == false) {
      await flutterTts.setLanguage("vi"); 
    }
    await flutterTts.setSpeechRate(0.4);   
    await flutterTts.setVolume(1.0);       
    await flutterTts.setPitch(1.0);        
  }

  Future<void> _speak(String text) async {
    String cleanText = text.replaceAll(RegExp(r'[*#_`]'), '');
    await flutterTts.speak(cleanText);
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _loadUserAndGreet() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('username') ?? "Học viên";
    setState(() {
      _username = name;
      _messages.add({
        "sender": "ai", 
        "text": "Chào $_username! Bạn hãy bấm biểu tượng 📎 để tải tài liệu PDF lên, sau đó mình sẽ hỗ trợ bạn học tập nhé!"
      });
    });
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Đã lưu vào Sổ tay!"), backgroundColor: Colors.teal)
        );
      }
    } catch (e) {
      print("Lỗi lưu nhanh: $e");
    }
  }

  Future<void> _uploadPDF() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom, 
      allowedExtensions: ['pdf'], 
      withData: true
    );
    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đang gửi file...'), duration: Duration(seconds: 2))
    );

    try {
      final request = http.MultipartRequest('POST', Uri.parse('$apiUrl/api/upload'));
      request.fields['user_id'] = _username; 

      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes(
          'file', result.files.single.bytes!, filename: result.files.single.name
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          'file', result.files.single.path!
        ));
      }
      
      final response = await request.send();
      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ AI đã học xong tài liệu này!'), backgroundColor: Colors.green)
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: ${response.statusCode}'), backgroundColor: Colors.red)
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Không kết nối được Backend.'), backgroundColor: Colors.red)
      );
    }
  }

  Future<void> _sendMessage() async {
    String text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({"sender": "user", "text": text});
      _messages.add({"sender": "ai", "text": "Đang suy nghĩ..."}); 
      _controller.clear();
    });

    try {
      final response = await http.post(
        Uri.parse("$apiUrl/api/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": _username, "message": text}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)); 
        setState(() {
          _messages.removeLast();
          _messages.add({"sender": "ai", "text": data["data"]["content"] ?? "Lỗi nội dung"});
        });
      } else {
        setState(() {
          _messages.removeLast();
          _messages.add({"sender": "ai", "text": "Cần tải PDF lên trước khi hỏi Sang nhé!"});
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _messages.add({"sender": "ai", "text": "Lỗi kết nối máy chủ."});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Trò chuyện cùng AI', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.white), onPressed: _uploadPDF),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg["sender"] == "user";
                
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blueAccent : Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(15),
                        topRight: const Radius.circular(15),
                        bottomLeft: Radius.circular(isUser ? 15 : 0),
                        bottomRight: Radius.circular(isUser ? 0 : 15),
                      ),
                    ),
                    child: isUser 
                      ? Text(msg["text"]!, style: const TextStyle(fontSize: 16, color: Colors.white))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarkdownBody(
                              data: msg["text"]!,
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(fontSize: 16, color: Colors.black87),
                              ),
                            ),
                            if (msg["text"] != "Đang suy nghĩ...") ...[
                              const Divider(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.volume_up, size: 20, color: Colors.orange),
                                    onPressed: () => _speak(msg["text"]!), 
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.bookmark_add, size: 20, color: Colors.teal),
                                    onPressed: () => _quickSaveNote(msg["text"]!),
                                  ),
                                ],
                              )
                            ]
                          ],
                        ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(15.0),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Hỏi AI về tài liệu...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendMessage),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}