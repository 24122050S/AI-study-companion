import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_markdown/flutter_markdown.dart';

import 'quiz_review_screen.dart';
import 'api_constants.dart';

const Color cBg         = Color(0xFFEAF6F2); 
const Color cMint       = Color(0xFF6DBFAB); 
const Color cMintDark   = Color(0xFF4A9E8C); 
const Color cCoral      = Color(0xFFE8604A); 
const Color cCoralLight = Color(0xFFF5957F); 
const Color cDark       = Color(0xFF1D3330); 
const Color cCard       = Color(0xFFFFFFFF); 
const Color cCardTinted = Color(0xFFF0FAF7); 
const Color cText       = Color(0xFF2C4A45); 
const Color cTextLight  = Color(0xFF7A9E99); 
const Color cYellow     = Color(0xFFFFCC5C); 
const Color cPeach      = Color(0xFFF5C8B8); 
const Color cBorder     = Color(0xFFD2E8E3);

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

class _QuizScreenState extends State<QuizScreen> with TickerProviderStateMixin {
  List<dynamic> _questions = [];
  bool _isLoading = false;
  bool _isFinished = false;

  Map<int, String> _selectedAnswers = {};
  Map<int, bool> _aiShortAnswerResults = {};
  Timer? _timer;
  late int _secondsRemaining;

  late final AnimationController _uiController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;
  late final AnimationController _floatCtrl;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.timeLimit;

    _floatCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..repeat(reverse: true);

    _uiController = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _fadeIn = CurvedAnimation(parent: _uiController, curve: Curves.easeOutCubic);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _uiController, curve: Curves.easeOutCubic));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _uiController.forward(from: 0);
    });

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
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  Color _themeColor() {
    if (widget.modeName == "Ôn tập lỗi sai") return const Color(0xFF9C6BC5); 
    return widget.timeLimit > 0 ? cCoral : cMint;
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
    _uiController.forward(from: 0);

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
    } catch (_) {
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
      builder: (_) => const Center(child: CircularProgressIndicator(color: cMint)),
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
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError("Lỗi kết nối khi phân tích điểm yếu.");
    }
  }

  void _showReportDialog(String report, List<dynamic> remedialQuiz) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: cCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: cMint, width: 2)),
        title: Row(children: [
          const Icon(Icons.health_and_safety, color: cMint, size: 28),
          const SizedBox(width: 10),
          const Text("Báo Cáo Điểm Yếu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cDark)),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: MarkdownBody(
              data: report,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 15, height: 1.55, color: cText),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: const Text("Bỏ qua", style: TextStyle(color: cTextLight)),
          ),
          if (remedialQuiz.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.edit_document, color: cCard, size: 18),
              label: const Text("Làm bài khắc phục", style: TextStyle(color: cCard, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: cMint),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacement(context, MaterialPageRoute(
                  builder: (_) => QuizScreen(
                    modeName: "Ôn tập lỗi sai", numQuestions: remedialQuiz.length,
                    timeLimit: 0, username: widget.username,
                    notebookId: widget.notebookId, preloadedQuestions: remedialQuiz,
                  ),
                ));
              },
            ),
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
        backgroundColor: cCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: const Row(
          children: [
            CircularProgressIndicator(color: cCoral),
            SizedBox(width: 20),
            Expanded(child: Text("Giám khảo AI đang chấm bài tự luận, vui lòng đợi...", style: TextStyle(fontWeight: FontWeight.w500, color: cText))),
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
            if (isCorrect) score++;
          }
        }
      } catch (_) {}
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
        ).catchError((_) {});

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
                 content: Text("🎉 ${gateData['message']}", style: const TextStyle(fontWeight: FontWeight.bold, color: cCard)),
                 backgroundColor: cMintDark,
                 duration: const Duration(seconds: 5),
               ));
           } else if (gateData['action'] == 'blocked') {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                 content: Text("⚠️ ${gateData['message']}", style: const TextStyle(fontWeight: FontWeight.bold, color: cCard)),
                 backgroundColor: cCoral,
                 duration: const Duration(seconds: 6),
               ));
           }
        }
      }
    } catch (_) {}

    _showResultDialog(score);
  }

  void _showResultDialog(int score) {
    final pct = (score / _questions.length * 100).toStringAsFixed(1);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: cCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: cMint, width: 2)),
        title: Text("Kết quả ${widget.modeName}", style: const TextStyle(color: cDark, fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(shape: BoxShape.circle, color: cMint.withOpacity(0.12)),
            child: Text("$pct%", style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: cMint)),
          ),
          const SizedBox(height: 12),
          Text("Bạn đúng $score / ${_questions.length} câu",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cText)),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
            TextButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              child: const Text("Về trang chủ", style: TextStyle(color: cTextLight)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cMintDark),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => QuizReviewScreen(questions: _questions, userAnswers: _selectedAnswers),
                ));
              },
              child: const Text("Xem đáp án", style: TextStyle(color: cCard, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cCoral),
              onPressed: () { Navigator.pop(context); _fetchQuiz(); },
              child: const Text("Làm lại", style: TextStyle(color: cCard, fontWeight: FontWeight.bold)),
            ),
            if (score < _questions.length)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: cDark),
                icon: const Icon(Icons.auto_awesome, color: cYellow, size: 18),
                label: const Text("Bắt mạch điểm yếu", style: TextStyle(color: cCard, fontWeight: FontWeight.bold)),
                onPressed: () { Navigator.pop(context); _analyzeWeakness(); },
              ),
          ]),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, color: cCard)), backgroundColor: cCoral),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _uiController.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _themeColor();
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: cBg,
      body: Column(
        children: [
          _buildTopBar(themeColor),
          Expanded(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: isDesktop
                    ? _buildDesktopLayout(themeColor, size)
                    : _buildMobileLayout(themeColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(Color themeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: cCard,
        boxShadow: [BoxShadow(color: cMint.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _TopBarBtn(icon: Icons.arrow_back_rounded, color: cBg, iconColor: cDark, onTap: () => Navigator.pop(context)),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: themeColor.withOpacity(0.3), width: 1),
              ),
              child: Row(children: [
                Icon(Icons.quiz_rounded, color: themeColor, size: 16),
                const SizedBox(width: 6),
                Text(widget.modeName, style: TextStyle(color: themeColor, fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cDark.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(widget.difficulty, style: const TextStyle(color: cText, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const Spacer(),
            if (_questions.isNotEmpty && !_isFinished && widget.timeLimit > 0)
              _TimerChip(seconds: _secondsRemaining, format: _formatTime),
            const SizedBox(width: 14),
            _TopBarBtn(icon: Icons.home_rounded, color: cBg, iconColor: cDark, onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(Color themeColor, Size size) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 60,
          child: _isLoading
              ? _buildLoading(themeColor)
              : _questions.isEmpty
                  ? _buildStartScreen(themeColor)
                  : _buildQuizList(themeColor),
        ),
        SizedBox(
          width: size.width * 0.38,
          child: _buildIllustrationPanel(themeColor),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(Color themeColor) {
    return _isLoading
        ? _buildLoading(themeColor)
        : _questions.isEmpty
            ? _buildStartScreen(themeColor)
            : Stack(
                children: [
                  _buildQuizList(themeColor),
                  if (!_isFinished)
                    Positioned(
                      right: 20,
                      bottom: 20,
                      child: _FloatingSubmit(color: themeColor, onPressed: _submitQuiz),
                    ),
                ],
              );
  }

  Widget _buildIllustrationPanel(Color themeColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cMint.withOpacity(0.08), cPeach.withOpacity(0.15)],
        ),
        border: Border(left: BorderSide(color: cMint.withOpacity(0.2), width: 1.5)),
      ),
      child: Stack(
        children: [
          Positioned(top: -60, right: -60,
            child: Container(width: 250, height: 250,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cPeach.withOpacity(0.35)))),
          Positioned(bottom: -40, left: -40,
            child: Container(width: 180, height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cMint.withOpacity(0.25)))),

          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedBuilder(
                    animation: _floatCtrl,
                    builder: (_, child) {
                      final dy = math.sin(_floatCtrl.value * math.pi * 2) * 8;
                      return Transform.translate(offset: Offset(0, dy), child: child);
                    },
                    child: Container(
                      height: 300,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: cMint.withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 12)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/images/quiz_illustration.jpg',
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildProgressCard(themeColor),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildTipsCard(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(Color themeColor) {
    if (_questions.isEmpty) return const SizedBox.shrink();
    final answered = _selectedAnswers.length;
    final total = _questions.length;
    final progress = total > 0 ? answered / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: cMint.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Tiến độ", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cDark)),
              Text("$answered/$total câu", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: themeColor)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: cMint.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(themeColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipsCard() {
    const tips = [
      "📖 Đọc kỹ câu hỏi trước khi chọn",
      "⏱️ Phân bổ thời gian đều cho mỗi câu",
      "💡 Loại trừ đáp án sai trước",
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cCoralLight.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cCoral.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lightbulb_rounded, color: cYellow, size: 16),
            const SizedBox(width: 6),
            Text("Mẹo thi", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: cCoral)),
          ]),
          const SizedBox(height: 10),
          ...tips.map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(t, style: const TextStyle(fontSize: 11.5, color: cText, height: 1.4)),
          )),
        ],
      ),
    );
  }

  Widget _buildStartScreen(Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: cCard,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: color.withOpacity(0.3), width: 2),
              boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 12))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12)),
                child: Icon(widget.timeLimit > 0 ? Icons.timer_outlined : Icons.menu_book_rounded, color: color, size: 48),
              ),
              const SizedBox(height: 24),
              Text(widget.modeName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cDark)),
              const SizedBox(height: 10),
              Text(
                widget.timeLimit > 0
                    ? "Thời gian: ${_formatTime(widget.timeLimit)}\nSố lượng: ${widget.numQuestions} câu"
                    : "Luyện tập thoải mái\nSố lượng: ${widget.numQuestions} câu",
                style: const TextStyle(fontSize: 15, color: cTextLight, fontWeight: FontWeight.w500, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, color: cCard, size: 22),
                  label: const Text("BẮT ĐẦU NGAY", style: TextStyle(color: cCard, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
                  onPressed: _fetchQuiz,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(Color themeColor) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
        decoration: BoxDecoration(
          color: cCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: themeColor.withOpacity(0.15), blurRadius: 20)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: themeColor, strokeWidth: 3),
          const SizedBox(width: 18),
          const Text("Đang khởi tạo bài thi...", style: TextStyle(color: cDark, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildQuizList(Color color) {
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
          itemCount: _questions.length,
          itemBuilder: (context, index) {
            final q = _questions[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _buildQuestionCard(q, index, color),
                ),
              ),
            );
          },
        ),
        if (_questions.isNotEmpty && !_isFinished)
          Positioned(
            right: 30, bottom: 30,
            child: _FloatingSubmit(color: color, onPressed: _submitQuiz),
          ),
      ],
    );
  }

  Widget _buildQuestionCard(dynamic q, int index, Color color) {
    String type = q['type'] ?? 'multiple_choice';

    return Container(
      decoration: BoxDecoration(
        color: cCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: cMint.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                            decoration: BoxDecoration(color: cCardTinted, borderRadius: BorderRadius.circular(8), border: Border.all(color: cMint.withOpacity(0.5))),
                            child: Text("💡 ${q['concept']}", style: TextStyle(fontSize: 12, color: cMintDark, fontWeight: FontWeight.bold)),
                          ),
                        if (q['source_page'] != null && q['source_page'].toString().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: cCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: cBorder)),
                            child: Text("📄 Trang ${q['source_page']}", style: const TextStyle(fontSize: 12, color: cTextLight)),
                          ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                      child: Center(
                        child: Text("${index + 1}", style: const TextStyle(color: cCard, fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        type == 'fill_in_blank' 
                            ? "Kéo từ thích hợp vào các ô trống:"
                            : (q['question'] ?? "").toString(),
                        style: const TextStyle(color: cDark, fontSize: 16, fontWeight: FontWeight.w800, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Builder(
                  builder: (context) {
                    if (type == 'multiple_choice') {
                      return Column(
                        children: List<Widget>.from((q['options'] as List).map((opt) {
                          final String optText = opt.toString();
                          final bool selected = _selectedAnswers[index] == optText;
                          final bool isCorrect = _isFinished && optText == q['answer'];
                          final bool isWrong = _isFinished && selected && optText != q['answer'];

                          return _OptionTile(
                            text: optText,
                            selected: selected,
                            enabled: !_isFinished,
                            accent: color,
                            state: isCorrect ? _OptionState.correct : isWrong ? _OptionState.wrong : _OptionState.normal,
                            onTap: () {
                              if (_isFinished) return;
                              setState(() => _selectedAnswers[index] = optText);
                            },
                          );
                        })),
                      );
                    } 
                    
                    // 🚀 GIAO DIỆN ĐÚNG SAI 2 CỘT MỚI CHUẨN THI THPT (BÊN PHẢI MỆNH ĐỀ)
                    else if (type == 'true_false') {
                      List<dynamic> tfOptions = q['options'] ?? [];
                      String currentAnsStr = _selectedAnswers[index] ?? "";
                      List<String> currentSelections = currentAnsStr.split("|");
                      if (currentSelections.length < tfOptions.length) {
                        List<String> newSelections = List.filled(tfOptions.length, "");
                        for(int i = 0; i < currentSelections.length; i++) {
                          if (i < tfOptions.length) newSelections[i] = currentSelections[i];
                        }
                        currentSelections = newSelections;
                      }
                      
                      String correctAnsStr = q['answer']?.toString() ?? "";
                      List<String> correctAnswers = correctAnsStr.split("|");

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Tiêu đề 2 cột Đ - S
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, right: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 36, child: const Center(child: Text("Đ", style: TextStyle(fontWeight: FontWeight.w900, color: cMintDark, fontSize: 16)))),
                                const SizedBox(width: 12),
                                SizedBox(width: 36, child: const Center(child: Text("S", style: TextStyle(fontWeight: FontWeight.w900, color: cCoral, fontSize: 16)))),
                              ]
                            )
                          ),
                          ...List.generate(tfOptions.length, (optIndex) {
                            String optText = tfOptions[optIndex].toString();
                            String myChoice = currentSelections[optIndex]; 
                            String correctChoice = optIndex < correctAnswers.length ? correctAnswers[optIndex] : "";
                            
                            bool isCorrectRow = _isFinished && myChoice.isNotEmpty && myChoice.toLowerCase() == correctChoice.toLowerCase();
                            bool isWrongRow = _isFinished && myChoice.isNotEmpty && myChoice.toLowerCase() != correctChoice.toLowerCase();
                            bool isMissedRow = _isFinished && myChoice.isEmpty;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: _isFinished 
                                    ? (isCorrectRow ? cMint.withOpacity(0.1) : (isWrongRow || isMissedRow ? cCoral.withOpacity(0.1) : cCardTinted))
                                    : cCardTinted,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isFinished
                                      ? (isCorrectRow ? cMint : (isWrongRow || isMissedRow ? cCoral : cBorder))
                                      : cBorder,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("${String.fromCharCode(65 + optIndex)}. $optText", style: const TextStyle(fontSize: 14.5, color: cDark, fontWeight: FontWeight.w600, height: 1.4)),
                                        if (_isFinished && (isWrongRow || isMissedRow)) ...[
                                          const SizedBox(height: 6),
                                          Text("Đáp án đúng: $correctChoice", style: const TextStyle(color: cCoral, fontWeight: FontWeight.bold, fontSize: 12)),
                                        ]
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Nút chọn ĐÚNG
                                  GestureDetector(
                                    onTap: () {
                                      if (!_isFinished) {
                                        setState(() {
                                          currentSelections[optIndex] = "Đúng";
                                          _selectedAnswers[index] = currentSelections.join("|");
                                        });
                                      }
                                    },
                                    child: Container(
                                      width: 36, height: 36,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: myChoice == "Đúng" ? cMintDark : Colors.transparent,
                                        border: Border.all(color: myChoice == "Đúng" ? cMintDark : cBorder, width: 2),
                                      ),
                                      child: Center(
                                        child: Text("Đ", style: TextStyle(
                                          color: myChoice == "Đúng" ? Colors.white : cTextLight,
                                          fontWeight: FontWeight.bold,
                                        )),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Nút chọn SAI
                                  GestureDetector(
                                    onTap: () {
                                      if (!_isFinished) {
                                        setState(() {
                                          currentSelections[optIndex] = "Sai";
                                          _selectedAnswers[index] = currentSelections.join("|");
                                        });
                                      }
                                    },
                                    child: Container(
                                      width: 36, height: 36,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: myChoice == "Sai" ? cCoral : Colors.transparent,
                                        border: Border.all(color: myChoice == "Sai" ? cCoral : cBorder, width: 2),
                                      ),
                                      child: Center(
                                        child: Text("S", style: TextStyle(
                                          color: myChoice == "Sai" ? Colors.white : cTextLight,
                                          fontWeight: FontWeight.bold,
                                        )),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                        ],
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
                              child: Text(parts[i], style: const TextStyle(fontSize: 15, height: 1.6, color: cText)),
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
                                      color: currentSelection.isEmpty ? cCardTinted : color.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: candidateData.isNotEmpty 
                                          ? cCoral 
                                          : (currentSelection.isEmpty ? cMint.withOpacity(0.3) : color)
                                      ),
                                    ),
                                    child: Text(
                                      currentSelection.isEmpty ? "${i + 1}" : currentSelection,
                                      style: TextStyle(
                                        color: currentSelection.isEmpty ? cTextLight : cDark, 
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

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: paragraphWidgets,
                          ),
                          const SizedBox(height: 25),
                          if (!_isFinished)
                            Wrap(
                              spacing: 10, runSpacing: 10,
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
                                      child: Text(optStr, style: const TextStyle(color: cCard, fontWeight: FontWeight.bold, fontSize: 16)),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.3, 
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                                      decoration: BoxDecoration(color: cTextLight, borderRadius: BorderRadius.circular(8)),
                                      child: Text(optStr, style: const TextStyle(color: cCard)),
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
                      );
                    } 
                    
                    else {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: TextField(
                          enabled: !_isFinished, 
                          style: const TextStyle(color: cDark),
                          decoration: InputDecoration(
                            hintText: "Nhập câu trả lời của bạn...",
                            hintStyle: const TextStyle(color: cTextLight),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: cMint)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cMint.withOpacity(0.5))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: cMint, width: 2)),
                            filled: true,
                            fillColor: _isFinished ? cBg : cCard,
                            prefixIcon: Icon(Icons.edit_note, color: color),
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
                  if (type != 'true_false')
                    Padding(
                      padding: const EdgeInsets.only(top: 15.0),
                      child: Builder(
                        builder: (context) {
                          bool isCorrect = false;

                          if (type == 'short_answer') {
                            isCorrect = _aiShortAnswerResults[index] ?? false;
                          } else {
                            String userAnswer = (_selectedAnswers[index] ?? "").trim().toLowerCase().replaceAll(' | ', '|').replaceAll(' |', '|').replaceAll('| ', '|');
                            String correctAnswer = (q['answer'] ?? "").toString().trim().toLowerCase().replaceAll(' | ', '|').replaceAll(' |', '|').replaceAll('| ', '|');
                            isCorrect = userAnswer == correctAnswer;
                          }

                          String displayAnswer = (q['answer'] ?? "").toString().replaceAll('|', ', ');

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isCorrect ? cMint.withOpacity(0.12) : cCoral.withOpacity(0.1),
                              border: Border.all(
                                color: isCorrect ? cMint : cCoral,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                  color: isCorrect ? cMintDark : cCoral,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isCorrect 
                                          ? (type == 'short_answer' ? "✅ Tuyệt vời! Giám khảo AI chấm bạn ĐÚNG Ý." : "✅ Tuyệt vời! Bạn đã chọn chính xác.")
                                          : "❌ Đáp án đúng là: $displayAnswer",
                                        style: TextStyle(
                                          color: isCorrect ? cMintDark : cCoral,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                      if (type == 'short_answer' || type == 'fill_in_blank') ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          "Câu trả lời của bạn: ${(_selectedAnswers[index] ?? 'Bỏ trống').replaceAll('|', ', ')}",
                                          style: TextStyle(color: cTextLight.withOpacity(0.8), fontStyle: FontStyle.italic, fontSize: 13),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      ),
                    ),

                  if (q['explanation'] != null && q['explanation'].toString().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 15),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cYellow.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cYellow.withOpacity(0.3))
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lightbulb_rounded, color: cYellow, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Giải thích: ${q['explanation']}",
                              style: TextStyle(color: cDark.withOpacity(0.8), fontSize: 14, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBarBtn extends StatelessWidget {
  final IconData icon;
  final Color color, iconColor;
  final VoidCallback onTap;
  const _TopBarBtn({required this.icon, required this.color, required this.iconColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }
}

class _TimerChip extends StatelessWidget {
  final int seconds;
  final String Function(int) format;
  const _TimerChip({required this.seconds, required this.format});

  @override
  Widget build(BuildContext context) {
    final isUrgent = seconds <= 30;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isUrgent ? cCoral : cMint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.timer_rounded, color: cCard, size: 15),
        const SizedBox(width: 6),
        Text(format(seconds), style: const TextStyle(color: cCard, fontWeight: FontWeight.w900, fontSize: 14)),
      ]),
    );
  }
}

enum _OptionState { normal, correct, wrong }

class _OptionTile extends StatelessWidget {
  final String text;
  final bool selected, enabled;
  final Color accent;
  final _OptionState state;
  final VoidCallback onTap;

  const _OptionTile({
    required this.text, required this.selected, required this.enabled,
    required this.accent, required this.state, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color fill = cCardTinted;
    Color border = cMint.withOpacity(0.25);
    Color textCol = cText;
    Color circleColor = cTextLight;

    if (selected && state == _OptionState.normal) {
      fill = accent.withOpacity(0.12);
      border = accent;
      textCol = cDark;
      circleColor = accent;
    }
    if (state == _OptionState.correct) {
      fill = cMint.withOpacity(0.15);
      border = cMint;
      textCol = cMintDark;
      circleColor = cMint;
    } else if (state == _OptionState.wrong) {
      fill = cCoral.withOpacity(0.1);
      border = cCoral;
      textCol = cCoral;
      circleColor = cCoral;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.5),
              boxShadow: selected || state != _OptionState.normal
                  ? [BoxShadow(color: border.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]
                  : [],
            ),
            child: Row(children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: circleColor, width: 2),
                  color: (selected || state != _OptionState.normal) ? circleColor.withOpacity(0.15) : Colors.transparent,
                ),
                child: Center(
                  child: selected || state != _OptionState.normal
                      ? Icon(state == _OptionState.wrong ? Icons.close : Icons.check, size: 14, color: circleColor)
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(text, style: TextStyle(color: textCol, fontWeight: FontWeight.w600, fontSize: 14.5, height: 1.4)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FloatingSubmit extends StatelessWidget {
  final Color color;
  final VoidCallback onPressed;
  const _FloatingSubmit({required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: color,
      elevation: 6,
      onPressed: onPressed,
      child: const Icon(Icons.send_rounded, color: cCard, size: 24),
    );
  }
}