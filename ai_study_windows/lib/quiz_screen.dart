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
  final String quizType;
  final List<dynamic>? preloadedQuestions; 
  final String? focusTopic; 

  const QuizScreen({
    super.key, 
    required this.modeName, 
    required this.numQuestions, 
    required this.timeLimit,
    required this.username,
    required this.notebookId, 
    this.difficulty = "Trung bình",
    this.quizType = "Trộn lẫn",
    this.preloadedQuestions, 
    this.focusTopic, 
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  
  List<dynamic> _questions = [];
  bool _isLoading = false;
  bool _isFinished = false;

  Map<int, String> _selectedAnswers = {};
  Map<int, bool> _aiShortAnswerResults = {}; 
  Timer? _timer;
  late int _secondsRemaining;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.timeLimit;
    _fetchQuiz(); 
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
      _aiShortAnswerResults = {};
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
          "difficulty": widget.difficulty,
          "quiz_type": widget.quizType,
          "focus_topic": widget.focusTopic 
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
    List<String> correctConcepts = []; 

    for (int i = 0; i < _questions.length; i++) {
      String type = _questions[i]['type'] ?? "";
      bool isCorrect = false;
      
      if (type == 'short_answer') {
        isCorrect = _aiShortAnswerResults[i] ?? false;
      } else {
        String userAnswer = (_selectedAnswers[i] ?? "").trim().toLowerCase().replaceAll(' | ', '|').replaceAll(' |', '|').replaceAll('| ', '|');
        String correctAnswer = (_questions[i]['answer'] ?? "").toString().trim().toLowerCase().replaceAll(' | ', '|').replaceAll(' |', '|').replaceAll('| ', '|');
        isCorrect = userAnswer == correctAnswer;
      }

      String concept = _questions[i]['concept'] ?? "Kiến thức chung";
      String question = _questions[i]['question'];

      if (!isCorrect) {
        wrongQuestions.add("[$concept] - $question");
      } else {
        if (!correctConcepts.contains(concept) && concept != "Kiến thức chung") {
          correctConcepts.add(concept); 
        }
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
          "correct_questions": correctConcepts, 
        }),
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (decoded['status'] == 'success') {
           final data = decoded['data'];
           String report = data['report'] ?? "Không có báo cáo.";
           List<dynamic> remedialQuiz = data['quiz'] ?? [];
           _showReportDialog(report, remedialQuiz);
        } else {
           _showError(decoded['message'] ?? "Lỗi phân tích từ Server.");
        }
      } else {
        _showError("Lỗi máy chủ: ${response.statusCode}");
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
          height: 400, 
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: const Row(
          children: [
            CircularProgressIndicator(color: Colors.orange),
            SizedBox(width: 20),
            Expanded(child: Text("Giám khảo AI đang chấm bài tự luận, vui lòng đợi...", style: TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );

    int score = 0;
    List<Map<String, dynamic>> shortAnswersToGrade = [];
    List<int> shortAnswerIndices = [];

    for (int i = 0; i < _questions.length; i++) {
      String type = _questions[i]['type'] ?? "";
      String userAnswer = (_selectedAnswers[i] ?? "").trim();
      String correctAnswer = (_questions[i]['answer'] ?? "").toString().trim();

      if (type == 'short_answer') {
        shortAnswersToGrade.add({
          "question": _questions[i]['question'],
          "correct_answer": correctAnswer,
          "user_answer": userAnswer
        });
        shortAnswerIndices.add(i); 
      } else {
        String cleanUser = userAnswer.toLowerCase().replaceAll(' | ', '|').replaceAll(' |', '|').replaceAll('| ', '|');
        String cleanCorrect = correctAnswer.toLowerCase().replaceAll(' | ', '|').replaceAll(' |', '|').replaceAll('| ', '|');
        if (cleanUser == cleanCorrect) {
          score++;
        }
      }
    }

    if (shortAnswersToGrade.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse("${ApiConstants.baseUrl}/api/quiz/grade_short_answers"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"items": shortAnswersToGrade}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          List<dynamic> aiResults = data["results"] ?? [];
          
          for (int k = 0; k < aiResults.length; k++) {
            int qIndex = shortAnswerIndices[k];
            bool isCorrect = aiResults[k] == true;
            _aiShortAnswerResults[qIndex] = isCorrect; 
            if (isCorrect) {
              score++;
            }
          }
        }
      } catch (e) { print("Lỗi kết nối Trọng tài AI: $e"); }
    }

    if (!mounted) return;
    Navigator.pop(context); 

    setState(() => _isFinished = true);

    try {
      await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/score"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username,
          "notebook_id": widget.notebookId, 
          "topic": widget.modeName,
          "score": score,
          "total": _questions.length
        }),
      );

      // 🚀 ĐẶT BOM HẸN GIỜ NHẮC NHỞ ÔN TẬP (4 TIẾNG SAU MỚI HIỆN)
      if (widget.focusTopic != null) {
        http.post(
          Uri.parse("${ApiConstants.baseUrl}/api/notifications"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "user_id": widget.username,
            "notebook_id": widget.notebookId,
            "title": "⏰ Đến giờ ôn tập rồi!",
            "message": "Đã 4 tiếng kể từ khi bạn học '${widget.focusTopic}'. Theo đường cong lãng quên, đây là lúc não bộ cần gợi nhớ. Hãy làm 1 bài Quiz nhỏ nhé!",
            "type": "warning",
            "delay_hours": 4 
          }),
        ).catchError((e) => print("Lỗi đặt lịch: $e"));

        final gateResponse = await http.post(
          Uri.parse("${ApiConstants.baseUrl}/api/roadmap/submit_gate"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "user_id": widget.username,
            "notebook_id": widget.notebookId,
            "topic": widget.focusTopic, 
            "score": score,
            "total": _questions.length
          }),
        );
        
        if (gateResponse.statusCode == 200) {
           final gateData = jsonDecode(utf8.decode(gateResponse.bodyBytes));
           if (!mounted) return;
           if (gateData['action'] == 'unlocked' || gateData['action'] == 'completed') {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                 content: Text("🎉 ${gateData['message']}"),
                 backgroundColor: Colors.green,
                 duration: const Duration(seconds: 5),
               ));
           } else if (gateData['action'] == 'blocked') {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                 content: Text("⚠️ ${gateData['message']}"),
                 backgroundColor: Colors.red,
                 duration: const Duration(seconds: 6),
               ));
           }
        }
      }

    } catch (e) { print("Lỗi lưu điểm: $e"); }

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
                onPressed: () => Navigator.pop(context),
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
              ? const Center(child: Text("Đang tải dữ liệu...")) 
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

                if (q['type'] != 'fill_in_blank')
                  Text("Câu ${index + 1}: ${q['question']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Divider(),
                
                Builder(
                  builder: (context) {
                    String type = q['type'] ?? 'multiple_choice';

                    if (type == 'multiple_choice' || type == 'true_false') {
                      return Column(
                        children: List<Widget>.from(q['options'].map((opt) {
                          return RadioListTile<String>(
                            title: Text(opt.toString()),
                            value: opt.toString(),
                            groupValue: _selectedAnswers[index],
                            activeColor: color,
                            onChanged: _isFinished ? null : (val) {
                              setState(() => _selectedAnswers[index] = val!);
                            },
                          );
                        })),
                      );
                    } 
                    
                    else if (type == 'fill_in_blank') {
                      List<dynamic> dragOptions = q['options'] ?? [];
                      
                      List<String> parts = q['question'].toString().split("___");
                      int numBlanks = parts.length > 1 ? parts.length - 1 : 0;

                      String currentAnsStr = _selectedAnswers[index] ?? "";
                      List<String> currentSelections = currentAnsStr.split("|");
                      if (currentSelections.length < numBlanks) {
                        List<String> newSelections = List.filled(numBlanks, "");
                        for(int i = 0; i < currentSelections.length; i++) {
                          if (i < numBlanks) newSelections[i] = currentSelections[i];
                        }
                        currentSelections = newSelections;
                      }

                      List<Widget> paragraphWidgets = [];
                      for (int i = 0; i < parts.length; i++) {
                        if (parts[i].isNotEmpty) {
                          paragraphWidgets.add(
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(parts[i], style: const TextStyle(fontSize: 16, height: 1.6)),
                            )
                          );
                        }
                        if (i < numBlanks) {
                          String currentSelection = currentSelections[i];
                          paragraphWidgets.add(
                            DragTarget<String>(
                              builder: (context, candidateData, rejectedData) {
                                return GestureDetector(
                                  onTap: () {
                                     if (!_isFinished) {
                                       setState(() {
                                         currentSelections[i] = "";
                                         _selectedAnswers[index] = currentSelections.join("|");
                                       });
                                     }
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: currentSelection.isEmpty ? Colors.grey.shade100 : Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: candidateData.isNotEmpty 
                                          ? Colors.orange 
                                          : (currentSelection.isEmpty ? Colors.grey.shade400 : Colors.blue)
                                      ),
                                    ),
                                    child: Text(
                                      currentSelection.isEmpty ? "${i + 1}" : currentSelection,
                                      style: TextStyle(
                                        color: currentSelection.isEmpty ? Colors.grey : Colors.blue.shade900, 
                                        fontWeight: FontWeight.bold
                                      ),
                                    ),
                                  ),
                                );
                              },
                              onAcceptWithDetails: (details) {
                                if (!_isFinished) {
                                  setState(() {
                                    currentSelections[i] = details.data;
                                    _selectedAnswers[index] = currentSelections.join("|");
                                  });
                                }
                              },
                            )
                          );
                        }
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Câu ${index + 1}: Kéo từ thích hợp vào các ô trống", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 15),
                            
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: paragraphWidgets,
                            ),
                            const SizedBox(height: 25),
                            
                            if (!_isFinished)
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: dragOptions.map((opt) {
                                  String optStr = opt.toString();
                                  bool isUsed = currentSelections.contains(optStr);
                                  
                                  return isUsed ? const SizedBox.shrink() : Draggable<String>(
                                    data: optStr,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                                        child: Text(optStr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.3, 
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                                        decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(8)),
                                        child: Text(optStr, style: const TextStyle(color: Colors.white)),
                                      )
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color)),
                                      child: Text(optStr, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                                    ),
                                  );
                                }).toList(),
                              )
                          ],
                        ),
                      );
                    } 
                    
                    else {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        child: TextField(
                          enabled: !_isFinished, 
                          decoration: InputDecoration(
                            hintText: "Nhập câu trả lời của bạn...",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: _isFinished ? Colors.grey.shade100 : Colors.white,
                            prefixIcon: const Icon(Icons.edit_note, color: Colors.purple),
                          ),
                          onChanged: (val) {
                            _selectedAnswers[index] = val;
                          },
                        ),
                      );
                    }
                  }
                ),
                
                if (_isFinished) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 15.0),
                    child: Builder(
                      builder: (context) {
                        String type = q['type'] ?? 'multiple_choice';
                        bool isCorrect = false;

                        if (type == 'short_answer') {
                          isCorrect = _aiShortAnswerResults[index] ?? false;
                        } else {
                          String userAnswer = (_selectedAnswers[index] ?? "").trim().toLowerCase().replaceAll(' | ', '|').replaceAll(' |', '|').replaceAll('| ', '|');
                          String correctAnswer = (q['answer'] ?? "").toString().trim().toLowerCase().replaceAll(' | ', '|').replaceAll(' |', '|').replaceAll('| ', '|');
                          isCorrect = userAnswer == correctAnswer;
                        }

                        String displayAnswer = (q['answer'] ?? "").toString().replaceAll('|', ', ');

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isCorrect 
                                ? (type == 'short_answer' ? "✅ Tuyệt vời! Giám khảo AI chấm bạn ĐÚNG Ý." : "✅ Tuyệt vời! Bạn đã điền chính xác.")
                                : "❌ Đáp án đúng là: $displayAnswer",
                              style: TextStyle(
                                color: isCorrect ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 15
                              ),
                            ),
                            if (type == 'short_answer' || type == 'fill_in_blank')
                              Text(
                                "Câu trả lời của bạn: ${(_selectedAnswers[index] ?? 'Bỏ trống').replaceAll('|', ', ')}",
                                style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                              ),
                          ],
                        );
                      }
                    ),
                  ),
                  
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