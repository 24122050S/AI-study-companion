import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';
import 'quiz_screen.dart';
import 'flashcard_screen.dart';

// ─── BẢNG MÀU "PASTEL EXPLORER" ───────────────────────────────────────────
const Color cPink     = Color(0xFFEF8F9A);
const Color cPinkDeep = Color(0xFFD95F72);
const Color cBlue     = Color(0xFF6B7EC5);
const Color cBlueSoft = Color(0xFF9BA8D8);
const Color cLeaf     = Color(0xFF7BA99B);
const Color cBg       = Color(0xFFFFF0ED);
const Color cCard     = Color(0xFFFFFFFF);
const Color cText     = Color(0xFF2D2438);
const Color cMuted    = Color(0xFF8B7D8F);
const Color cBorder   = Color(0xFFEDD8DC);
const Color cSurface  = Color(0xFFFBF4F5);
const Color cYellow   = Color(0xFFFFCC5C);

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

  // ─── CHỨC NĂNG CŨ ĐƯỢC GIỮ NGUYÊN: GỌI SONG SONG 2 API VÀ TRỘN DỮ LIỆU
  Future<void> _fetchCombinedHistory() async {
    setState(() => _isLoading = true);
    try {
      final quizUri = Uri.parse("${ApiConstants.baseUrl}/api/quiz/history/${widget.notebookId}?user_id=${widget.username}");
      final flashcardUri = Uri.parse("${ApiConstants.baseUrl}/api/flashcards/history/${widget.notebookId}?user_id=${widget.username}");

      final responses = await Future.wait([
        http.get(quizUri),
        http.get(flashcardUri),
      ]);

      List<dynamic> combinedList = [];

      if (responses[0].statusCode == 200) {
        final quizData = jsonDecode(utf8.decode(responses[0].bodyBytes))['data'] ?? [];
        for (var item in quizData) {
          item['study_type'] = 'quiz';
          combinedList.add(item);
        }
      }

      if (responses[1].statusCode == 200) {
        final flashcardData = jsonDecode(utf8.decode(responses[1].bodyBytes))['data'] ?? [];
        for (var item in flashcardData) {
          item['study_type'] = 'flashcard';
          combinedList.add(item);
        }
      }

      combinedList.sort((a, b) => DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at'])));

      setState(() {
        _historyItems = combinedList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Lỗi tải lịch sử tổng hợp: $e");
    }
  }

  // ─── CHỨC NĂNG CŨ ĐƯỢC GIỮ NGUYÊN: XỬ LÝ LÀM LẠI BÀI QUIZ
  Future<void> _retakeQuiz(int deckId, String title) async {
    _showLoading();
    try {
      final response = await http.get(
        Uri.parse("${ApiConstants.baseUrl}/api/quiz/deck/$deckId?user_id=${widget.username}")
      );
      if (!mounted) return;
      Navigator.pop(context);

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

  // ─── CHỨC NĂNG CŨ ĐƯỢC GIỮ NGUYÊN: XỬ LÝ ÔN LẠI FLASHCARD
  Future<void> _reviewFlashcard(int deckId) async {
    _showLoading();
    try {
      final response = await http.get(
        Uri.parse("${ApiConstants.baseUrl}/api/flashcards/deck/$deckId?user_id=${widget.username}")
      );
      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final cards = jsonDecode(utf8.decode(response.bodyBytes))['data'];
        Navigator.push(context, MaterialPageRoute(builder: (context) => FlashcardScreen(
          username: widget.username,
          notebookId: widget.notebookId,
          preloadedCards: cards,
        )));
      }
    } catch (e) { Navigator.pop(context); }
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
          decoration: BoxDecoration(
            color: cCard,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: cPinkDeep.withOpacity(0.15), blurRadius: 20)],
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: cPinkDeep, strokeWidth: 3),
            SizedBox(width: 18),
            Text("Đang mở bài học...", style: TextStyle(color: cText, fontSize: 15, fontWeight: FontWeight.bold, decoration: TextDecoration.none)),
          ]),
        ),
      ),
    );
  }

  // ─── GIAO DIỆN MỚI 2 CỘT (CÓ ẢNH Ở BÊN PHẢI GIỐNG HISTORY_SCREEN) ────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: _buildAppBar(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cột trái: Danh sách
          Expanded(
            flex: 5,
            child: _isLoading
                ? _buildLoadingState()
                : _historyItems.isEmpty
                    ? _buildEmptyState()
                    : _buildHistoryList(),
          ),
          // Cột phải: Hình ảnh (Thiết kế chèn ảnh y hệt HistoryScreen)
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: cPink.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 10)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/history_map_legend.jpg',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: cSurface,
                      width: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.image_not_supported_rounded, size: 64, color: cBorder),
                          const SizedBox(height: 16),
                          Text("Không tìm thấy ảnh", style: TextStyle(color: cMuted.withOpacity(0.5))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchCombinedHistory,
        backgroundColor: cPinkDeep,
        elevation: 6,
        child: const Icon(Icons.sync_rounded, color: Colors.white),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: cCard,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cPink.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cPink.withOpacity(0.3), width: 1.5),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: cText, size: 16),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: cPinkDeep.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.history_edu_rounded, color: cPinkDeep, size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            "NHẬT KÝ HỌC TẬP",
            style: TextStyle(color: cText, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.3),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cBlueSoft.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cBlueSoft.withOpacity(0.4)),
            ),
            child: const Text(
              "LEARNIFY",
              style: TextStyle(color: cBlue, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: cCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cBorder, width: 1.5),
            boxShadow: [BoxShadow(color: cPink.withOpacity(0.1), blurRadius: 15)],
          ),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: CircularProgressIndicator(color: cPinkDeep, strokeWidth: 2.5),
          ),
        ),
        const SizedBox(height: 16),
        const Text("Đang tải nhật ký...", style: TextStyle(color: cMuted, fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color: cSurface,
              shape: BoxShape.circle,
              border: Border.all(color: cBorder, width: 2),
            ),
            child: const Icon(Icons.history_toggle_off_rounded, size: 44, color: cMuted),
          ),
          const SizedBox(height: 20),
          const Text(
            "Chưa có lịch sử nào",
            style: TextStyle(color: cText, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            "Bạn chưa tạo bộ Flashcard hay bài Quiz nào trong Notebook này.",
            textAlign: TextAlign.center,
            style: TextStyle(color: cMuted, fontSize: 14, height: 1.5),
          ),
        ]),
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      physics: const BouncingScrollPhysics(),
      itemCount: _historyItems.length + 1, // +1 để chừa chỗ cho Header
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeroHeader();

        final item = _historyItems[index - 1];
        final bool isQuiz = item['study_type'] == 'quiz';
        
        final date = DateTime.parse(item['created_at']).toLocal();
        final dateString = "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";

        final Color itemAccent = isQuiz ? cYellow : cBlueSoft;
        final IconData itemIcon = isQuiz ? Icons.assignment_rounded : Icons.style_rounded;

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            decoration: BoxDecoration(
              color: cCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cBorder, width: 1.5),
              boxShadow: [
                BoxShadow(color: cPink.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  if (isQuiz) {
                    _retakeQuiz(item['id'], item['title']);
                  } else {
                    _reviewFlashcard(item['id']);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          color: itemAccent.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: itemAccent.withOpacity(0.4)),
                        ),
                        child: Icon(itemIcon, color: itemAccent, size: 22),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'],
                              style: const TextStyle(color: cText, fontWeight: FontWeight.w800, fontSize: 15, height: 1.3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: cSurface, borderRadius: BorderRadius.circular(6), border: Border.all(color: cBorder)),
                                child: Text(
                                  isQuiz ? "Trắc nghiệm (${item['difficulty']})" : "Thẻ ghi nhớ Flashcard",
                                  style: const TextStyle(color: cMuted, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.access_time_rounded, size: 12, color: cMuted),
                              const SizedBox(width: 4),
                              Text(dateString, style: const TextStyle(color: cMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: cPink.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: cPinkDeep, size: 22),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: cPink.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: const Text("STUDY LOG", style: TextStyle(color: cPinkDeep, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 12),
          const Text("Nhật ký ôn tập", style: TextStyle(color: cText, fontWeight: FontWeight.w900, fontSize: 28, height: 1.2)),
          const SizedBox(height: 12),
          const Text("Lưu trữ toàn bộ các bộ đề và bộ thẻ từ vựng bạn đã tạo. Ấn vào nút Play để ôn tập lại bất kỳ lúc nào.", style: TextStyle(color: cMuted, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}