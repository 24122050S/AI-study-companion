import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';
import 'quiz_screen.dart';

class QuizHistoryScreen extends StatefulWidget {
  final String username;
  final String notebookId;

  const QuizHistoryScreen({super.key, required this.username, required this.notebookId});

  @override
  State<QuizHistoryScreen> createState() => _QuizHistoryScreenState();
}

class _QuizHistoryScreenState extends State<QuizHistoryScreen> {
  List<dynamic> _historyDecks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  // 1. Gọi API lấy danh sách các Bộ Đề đã lưu
  Future<void> _fetchHistory() async {
    try {
      final response = await http.get(
        Uri.parse("${ApiConstants.baseUrl}/api/quiz/history/${widget.notebookId}?user_id=${widget.username}")
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes))['data'];
        setState(() {
          _historyDecks = data ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // 2. Khi ấn vào 1 bộ đề, gọi API lấy danh sách câu hỏi của bộ đó và mở QuizScreen
  Future<void> _retakeQuiz(int deckId, String title) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );

    try {
      final response = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/quiz/deck/$deckId"));
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (response.statusCode == 200) {
        final questions = jsonDecode(utf8.decode(response.bodyBytes))['data'];
        
        // Mở QuizScreen và truyền thẳng câu hỏi vào (Không cho gọi AI nữa)
        Navigator.push(context, MaterialPageRoute(builder: (context) => QuizScreen(
          modeName: "Làm lại: $title",
          numQuestions: questions.length,
          timeLimit: 0, // Không giới hạn thời gian khi làm lại
          username: widget.username,
          notebookId: widget.notebookId,
          preloadedQuestions: questions, // 👈 ĐÂY LÀ CHÌA KHÓA: Đổ câu hỏi cũ vào!
        )));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi tải đề thi!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Lịch sử Đề thi", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.orange,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _historyDecks.isEmpty
              ? const Center(child: Text("Bạn chưa tạo bộ đề nào trong dự án này."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _historyDecks.length,
                  itemBuilder: (context, index) {
                    final deck = _historyDecks[index];
                    // Định dạng lại ngày tháng
                    final date = DateTime.parse(deck['created_at']).toLocal();
                    final dateString = "${date.day}/${date.month}/${date.year} - ${date.hour}:${date.minute.toString().padLeft(2, '0')}";

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFFFF8E1),
                          child: Icon(Icons.history_edu, color: Colors.orange),
                        ),
                        title: Text(deck['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Độ khó: ${deck['difficulty']} • $dateString"),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () => _retakeQuiz(deck['id'], deck['title']),
                      ),
                    );
                  },
                ),
    );
  }
}