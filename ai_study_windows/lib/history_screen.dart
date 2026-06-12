import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'api_constants.dart';


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

class HistoryScreen extends StatefulWidget {
  final String username;
  const HistoryScreen({super.key, required this.username});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _history = [];
  String _aiRecommendation = "";
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  // Đã cập nhật: Gọi 2 API cùng lúc (Lấy Bảng điểm + Lấy Gợi ý AI)
  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
          Uri.parse("${ApiConstants.baseUrl}/api/history/${widget.username}"));
      
      final recResponse = await http.get(
          Uri.parse("${ApiConstants.baseUrl}/api/recommend/${widget.username}"));

      if (response.statusCode == 200) {
        setState(() {
          _history = jsonDecode(utf8.decode(response.bodyBytes));
          if (recResponse.statusCode == 200) {
            _aiRecommendation = jsonDecode(utf8.decode(recResponse.bodyBytes))['recommendation'] ?? "";
          }
        });
      }
    } catch (e) {
      debugPrint("Lỗi: $e");
    }
    setState(() => _isLoading = false);
  }

  void _refresh() {
    _fetchHistory();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Đã cập nhật dữ liệu", style: TextStyle(color: cCard, fontWeight: FontWeight.bold)),
      backgroundColor: cLeaf,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Color _scoreColor(double percent) {
    if (percent >= 80) return cLeaf;
    if (percent >= 50) return const Color(0xFFF5A623); // Cam vàng
    return cPinkDeep;
  }

  String _scoreLabel(double percent) {
    if (percent >= 80) return "Xuất sắc";
    if (percent >= 50) return "Khá";
    return "Cần cố gắng";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: _buildAppBar(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: _isLoading 
                ? _buildLoadingState() 
                : _history.isEmpty 
                    ? _buildEmptyState() 
                    : _buildHistoryList(),
          ),
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
        onPressed: _refresh,
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
            child: const Icon(Icons.emoji_events_rounded, color: cPinkDeep, size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            "BẢNG ĐIỂM",
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
        const Text("Đang tải dữ liệu...", style: TextStyle(color: cMuted, fontSize: 14, fontWeight: FontWeight.w600)),
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
            "Chưa có bài làm nào",
            style: TextStyle(color: cText, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            "Hãy bắt đầu luyện tập để theo dõi tiến độ của bạn!",
            textAlign: TextAlign.center,
            style: TextStyle(color: cMuted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cPinkDeep,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text("Bắt đầu ngay", style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
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
            child: const Text("HISTORY LOG", style: TextStyle(color: cPinkDeep, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 12),
          const Text("Hành trình của bạn", style: TextStyle(color: cText, fontWeight: FontWeight.w900, fontSize: 28, height: 1.2)),
          const SizedBox(height: 12),
          const Text("Theo dõi các cột mốc bạn đã đi qua. Mỗi bài kiểm tra là một bước tiến gần hơn đến mục tiêu.", style: TextStyle(color: cMuted, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      physics: const BouncingScrollPhysics(),
      itemCount: _history.length + 2, // Đã cộng thêm 2 item (1 cho tiêu đề, 1 cho khung AI)
      itemBuilder: (context, index) {
        
        // Vị trí số 1: Tiêu đề
        if (index == 0) return _buildHeroHeader();

        // Vị trí số 2: Khung Gợi ý Gia sư AI
        if (index == 1) {
          if (_aiRecommendation.isEmpty) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cYellow.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cYellow.withOpacity(0.5), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.psychology_rounded, color: Color(0xFFD4A847), size: 24),
                    SizedBox(width: 8),
                    Text("Gia sư AI gợi ý:", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFD4A847), fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _aiRecommendation,
                  style: const TextStyle(fontSize: 14.5, color: cText, height: 1.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        }

        // Vị trí số 3 trở đi: Lịch sử điểm số (Lùi index đi 2)
        final item = _history[index - 2];
        final double percent = (item['percentage'] ?? 0.0).toDouble();
        final Color accent = _scoreColor(percent);
        final String label = _scoreLabel(percent);
        final String dateStr = item['date']?.toString().split(' ')[0] ?? '';

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            decoration: BoxDecoration(
              color: cCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cBorder, width: 1.5),
              boxShadow: [
                BoxShadow(color: cPink.withOpacity(0.12), blurRadius: 15, offset: const Offset(0, 5)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _buildScoreRing(percent, accent),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['topic'] ?? 'Chủ đề',
                          style: const TextStyle(color: cText, fontWeight: FontWeight.w800, fontSize: 15, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.calendar_today_rounded, size: 12, color: cMuted),
                          const SizedBox(width: 4),
                          Text(dateStr, style: const TextStyle(color: cMuted, fontSize: 12, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                            child: Text(label, style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w800)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${item['score']}", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: accent, height: 1)),
                      Text("/ ${item['total']}", style: const TextStyle(color: cMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScoreRing(double percent, Color accent) {
    return SizedBox(
      width: 54, height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.08),
            ),
          ),
          CircularProgressIndicator(
            value: percent / 100,
            backgroundColor: cBorder,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
            strokeWidth: 4.5,
            strokeCap: StrokeCap.round,
          ),
          Text(
            "${percent.toInt()}%",
            style: const TextStyle(color: cText, fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}