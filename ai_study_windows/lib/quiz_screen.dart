import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; 
import 'package:flutter_markdown/flutter_markdown.dart';
import 'quiz_review_screen.dart';
import 'api_constants.dart';

class QuizScreen extends StatefulWidget {
  final String modeName;
  final int numQuestions;
  final int timeLimit; 
  final String username; 
  final String difficulty;
  final String notebookId; 
  final List<dynamic>? preloadedQuestions; 

  const QuizScreen({
    super.key, 
    required this.modeName, 
    required this.numQuestions, 
    required this.timeLimit,
    required this.username,
    required this.notebookId, 
    this.difficulty = "Trung bình",
    this.preloadedQuestions, 
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  
  List<dynamic> _questions = [];
  bool _isLoading = false;
  bool _isFinished = false;

  Map<int, String> _selectedAnswers = {};
  Timer? _timer;
  late int _secondsRemaining;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.timeLimit;
    _fetchQuiz(); // Tự động gọi hàm tải đề khi mở màn hình
  }

  void _startTimer() {
    if (widget.timeLimit <= 0) return; 
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _timer?.cancel();
          _submitQuiz(); 
        }
      });
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return "$minutes:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  Future<void> _fetchQuiz() async {
    setState(() {
      _isLoading = true;
      _questions = [];
      _selectedAnswers = {};
      _isFinished = false;
      _secondsRemaining = widget.timeLimit;
    });

    if (widget.preloadedQuestions != null && widget.preloadedQuestions!.isNotEmpty) {
      setState(() {
        _questions = widget.preloadedQuestions!;
        _startTimer();
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/quiz"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username, 
          "notebook_id": widget.notebookId, 
          "num_questions": widget.numQuestions, 
          "difficulty": widget.difficulty
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _questions = data["data"] ?? [];
          _startTimer(); 
        });
      } else {
        _showError("Lỗi từ server: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      _showError("Không thể kết nối Backend.");
    }
    setState(() => _isLoading = false);
  }

  Future<void> _analyzeWeakness() async {
    List<String> wrongQuestions = [];
    for (int i = 0; i < _questions.length; i++) {
      if (_selectedAnswers[i] != _questions[i]['answer']) {
        // 🚀 NÂNG CẤP: Gửi kèm tên Khái Niệm lên cho AI phân tích sâu hơn
        String concept = _questions[i]['concept'] ?? "Kiến thức chung";
        String question = _questions[i]['question'];
        wrongQuestions.add("[$concept] - $question");
      }
    }

    if (wrongQuestions.isEmpty) return; 

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.purple)),
    );

    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/analyze_weakness"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username,
          "notebook_id": widget.notebookId, 
          "wrong_questions": wrongQuestions,
        }),
      );

      if (!mounted) return;
      Navigator.pop(context); 

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes))['data'];
        String report = data['report'] ?? "Không có báo cáo.";
        List<dynamic> remedialQuiz = data['quiz'] ?? [];

        _showReportDialog(report, remedialQuiz);
      } else {
        _showError("Lỗi phân tích từ Server.");
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError("Lỗi kết nối khi phân tích điểm yếu.");
    }
  }

  void _showReportDialog(String report, List<dynamic> remedialQuiz) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.health_and_safety, color: Colors.purple, size: 28),
            SizedBox(width: 10),
            Text("Báo Cáo Điểm Yếu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: MarkdownBody(
              data: report,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); 
              Navigator.pop(context); 
            },
            child: const Text("Bỏ qua", style: TextStyle(color: Colors.grey)),
          ),
          if (remedialQuiz.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.edit_document, color: Colors.white, size: 18),
              label: const Text("Làm bài khắc phục", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              onPressed: () {
                Navigator.pop(context); 
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => QuizScreen(
                      modeName: "Ôn tập lỗi sai",
                      numQuestions: remedialQuiz.length,
                      timeLimit: 0, 
                      username: widget.username,
                      notebookId: widget.notebookId, 
                      preloadedQuestions: remedialQuiz, 
                    ),
                  ),
                );
              },
            )
        ],
      ),
    );
  }

  void _submitQuiz() async {
    _timer?.cancel();
    if (_isFinished) return;

    int score = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_selectedAnswers[i] == _questions[i]['answer']) {
        score++;
      }
    }

    setState(() => _isFinished = true);

    try {
      await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/score"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username,
          "topic": widget.modeName,
          "score": score,
          "total": _questions.length
        }),
      );
    } catch (e) {
      print("Lỗi lưu điểm: $e");
    }

    _showResultDialog(score);
  }

  void _showResultDialog(int score) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text("Kết quả ${widget.modeName}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Bạn đúng: $score / ${_questions.length} câu",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Phần trăm: ${(score / _questions.length * 100).toStringAsFixed(1)}%"),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context); 
                },
                child: const Text("Về trang chủ", style: TextStyle(color: Colors.grey)),
              ),
              
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () {
                  Navigator.pop(context); 
                  // Khi tắt popup, mảng _isFinished đã là true, giao diện sẽ tự xổ Giải thích ra
                },
                child: const Text("Xem đáp án & Giải thích", style: TextStyle(color: Colors.white)),
              ),

              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () {
                  Navigator.pop(context);
                  _fetchQuiz(); 
                },
                child: const Text("Làm lại", style: TextStyle(color: Colors.white)),
              ),

              if (score < _questions.length)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  label: const Text("Bắt mạch điểm yếu", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context); 
                    _analyzeWeakness(); 
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color themeColor = widget.timeLimit > 0 ? Colors.orange : Colors.green;
    if (widget.modeName == "Ôn tập lỗi sai") themeColor = Colors.purple; 

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.modeName, style: const TextStyle(color: Colors.white)),
        backgroundColor: themeColor,
        actions: [
          if (_questions.isNotEmpty && !_isFinished && widget.timeLimit > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  _formatTime(_secondsRemaining),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            )
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: themeColor))
          : _questions.isEmpty
              ? const Center(child: Text("Đang tải dữ liệu...")) // Đã bỏ nút Bắt Đầu thừa thãi
              : _buildQuizContent(themeColor),
      floatingActionButton: (_questions.isNotEmpty && !_isFinished)
          ? FloatingActionButton.extended(
              onPressed: _submitQuiz,
              label: const Text("Nộp bài", style: TextStyle(color: Colors.white)),
              icon: const Icon(Icons.send, color: Colors.white),
              backgroundColor: themeColor,
            )
          : null,
    );
  }

  Widget _buildQuizContent(Color color) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _questions.length,
      itemBuilder: (context, index) {
        final q = _questions[index];
        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🚀 NÂNG CẤP: HIỂN THỊ TAG KHÁI NIỆM VÀ NGUỒN (Nếu AI có gửi về)
                if (q['concept'] != null || q['source_page'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (q['concept'] != null && q['concept'].toString().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade100)),
                            child: Text("💡 ${q['concept']}", style: TextStyle(fontSize: 12, color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                          ),
                        if (q['source_page'] != null && q['source_page'].toString().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                            child: Text("📄 Trang ${q['source_page']}", style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                          ),
                      ],
                    ),
                  ),

                Text("Câu ${index + 1}: ${q['question']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Divider(),
                ...List<Widget>.from(q['options'].map((opt) {
                  return RadioListTile<String>(
                    title: Text(opt),
                    value: opt,
                    groupValue: _selectedAnswers[index],
                    activeColor: color,
                    onChanged: _isFinished ? null : (val) {
                      setState(() {
                        _selectedAnswers[index] = val!;
                      });
                    },
                  );
                })),
                
                // 🚀 NÂNG CẤP: KHU VỰC HIỂN THỊ ĐÁP ÁN VÀ GIẢI THÍCH CHI TIẾT
                if (_isFinished) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _selectedAnswers[index] == q['answer'] 
                        ? "✅ Tuyệt vời! Bạn đã chọn đúng." 
                        : "❌ Đáp án đúng là: ${q['answer']}",
                      style: TextStyle(
                        color: _selectedAnswers[index] == q['answer'] ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ),
                  
                  // Khung Giải thích màu vàng hiển thị lộng lẫy
                  if (q['explanation'] != null && q['explanation'].toString().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 15),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200)
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.menu_book, color: Colors.orange, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Giải thích: ${q['explanation']}",
                              style: TextStyle(color: Colors.orange.shade900, fontSize: 14, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ]
              ],
            ),
          ),
        );
      },
    );
  }
}