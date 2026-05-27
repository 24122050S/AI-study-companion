import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';
import 'quiz_screen.dart';
import 'flashcard_screen.dart';

class StudyHistoryScreen extends StatefulWidget {
  final String username;
  final String notebookId;

  const StudyHistoryScreen({super.key, required this.username, required this.notebookId});

  @override
  State<StudyHistoryScreen> createState() => _StudyHistoryScreenState();
}

class _StudyHistoryScreenState extends State<StudyHistoryScreen> {
  List<dynamic> _historyItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCombinedHistory();
  }

  // GỌI SONG SONG CẢ 2 API VÀ TRỘN DỮ LIỆU
  Future<void> _fetchCombinedHistory() async {
    setState(() => _isLoading = true);
    try {
      final quizUri = Uri.parse("${ApiConstants.baseUrl}/api/quiz/history/${widget.notebookId}?user_id=${widget.username}");
      final flashcardUri = Uri.parse("${ApiConstants.baseUrl}/api/flashcards/history/${widget.notebookId}?user_id=${widget.username}");

      // Chạy song song cả 2 request để tiết kiệm thời gian
      final responses = await Future.wait([
        http.get(quizUri),
        http.get(flashcardUri),
      ]);

      List<dynamic> combinedList = [];

      // Đọc lịch sử Quiz
      if (responses[0].statusCode == 200) {
        final quizData = jsonDecode(utf8.decode(responses[0].bodyBytes))['data'] ?? [];
        for (var item in quizData) {
          item['study_type'] = 'quiz'; // Đánh dấu loại dữ liệu
          combinedList.add(item);
        }
      }

      // Đọc lịch sử Flashcard
      if (responses[1].statusCode == 200) {
        final flashcardData = jsonDecode(utf8.decode(responses[1].bodyBytes))['data'] ?? [];
        for (var item in flashcardData) {
          item['study_type'] = 'flashcard'; // Đánh dấu loại dữ liệu
          combinedList.add(item);
        }
      }

      // SẮP XẾP: Bộ nào mới tạo gần đây nhất sẽ nhảy lên đầu danh sách
      combinedList.sort((a, b) => DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at'])));

      setState(() {
        _historyItems = combinedList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print("Lỗi tải lịch sử tổng hợp: $e");
    }
  }

  // XỬ LÝ KHI ẤN VÀO MỘT MỤC QUIZ CŨ
  Future<void> _retakeQuiz(int deckId, String title) async {
    _showLoading();
    try {
      // Thay dòng API cũ bằng dòng này (Thêm đuôi ?user_id=${widget.username}):
  final response = await http.get(
    Uri.parse("${ApiConstants.baseUrl}/api/quiz/deck/$deckId?user_id=${widget.username}")
  );
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (response.statusCode == 200) {
        final questions = jsonDecode(utf8.decode(response.bodyBytes))['data'];
        Navigator.push(context, MaterialPageRoute(builder: (context) => QuizScreen(
          modeName: "Làm lại: $title",
          numQuestions: questions.length,
          timeLimit: 0,
          username: widget.username,
          notebookId: widget.notebookId,
          preloadedQuestions: questions,
        )));
      }
    } catch (e) { Navigator.pop(context); }
  }

  // XỬ LÝ KHI ẤN VÀO MỘT BỘ FLASHCARD CŨ
  Future<void> _reviewFlashcard(int deckId) async {
    _showLoading();
    try {
      final response = await http.get(
    Uri.parse("${ApiConstants.baseUrl}/api/flashcards/deck/$deckId?user_id=${widget.username}")
  );
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (response.statusCode == 200) {
        final cards = jsonDecode(utf8.decode(response.bodyBytes))['data'];
        Navigator.push(context, MaterialPageRoute(builder: (context) => FlashcardScreen(
          username: widget.username,
          notebookId: widget.notebookId,
          preloadedCards: cards, // Đổ bộ thẻ cũ vào để học lại
        )));
      }
    } catch (e) { Navigator.pop(context); }
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.blueGrey)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text("Nhật ký Học tập", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueGrey,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blueGrey))
          : _historyItems.isEmpty
              ? const Center(child: Text("Bạn chưa có lịch sử luyện tập nào."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _historyItems.length,
                  itemBuilder: (context, index) {
                    final item = _historyItems[index];
                    final bool isQuiz = item['study_type'] == 'quiz';
                    
                    final date = DateTime.parse(item['created_at']).toLocal();
                    final dateString = "${date.day}/${date.month} - ${date.hour}:${date.minute.toString().padLeft(2, '0')}";

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        // Phân biệt Icon và màu sắc giữa Trắc nghiệm và Thẻ từ
                        leading: CircleAvatar(
                          backgroundColor: isQuiz ? const Color(0xFFFFF8E1) : const Color(0xFFF3E5F5),
                          child: Icon(
                            isQuiz ? Icons.assignment : Icons.style, 
                            color: isQuiz ? Colors.orange : Colors.purpleAccent
                          ),
                        ),
                        title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          isQuiz ? "Trắc nghiệm (${item['difficulty']}) • $dateString" : "Thẻ ghi nhớ Flashcard • $dateString",
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: const Icon(Icons.play_circle_outline, color: Colors.blueGrey),
                        onTap: () {
                          if (isQuiz) {
                            _retakeQuiz(item['id'], item['title']);
                          } else {
                            _reviewFlashcard(item['id']);
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }
}