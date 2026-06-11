import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';

// ── Bảng màu đồng bộ tông cam/vàng với ảnh road ─────────────────────────────
const Color _bg          = Color(0xFFFFF6F2);
const Color _cardWhite   = Color(0xFFFFFFFF);
const Color _orange      = Color(0xFFE8734A);
const Color _orangeLight = Color(0xFFF5A07A);
const Color _darkText    = Color(0xFF2C3E50);
const Color _midText     = Color(0xFF8A9BB0);
const Color _lineColor   = Color(0xFFEEE8E4);

class RoadmapScreen extends StatefulWidget {
  final String username;
  final String notebookId;

  const RoadmapScreen({super.key, required this.username, required this.notebookId});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  List<dynamic> _roadmapStages = [];
  int _currentStage = 1; // 🚀 BIẾN LƯU TRỮ TIẾN ĐỘ THUẬT TOÁN
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRoadmap();
  }

  // ── GIỮ NGUYÊN 100% LOGIC GỐC ────────────────────────────────────────────
  Future<void> _fetchRoadmap() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/roadmap"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username,
          "notebook_id": widget.notebookId,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _roadmapStages = data['data'] ?? [];
          _currentStage = data['current_stage'] ?? 1; // 🚀 ĐÓN DỮ LIỆU TỪ BACKEND
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải lộ trình: $e");
    }
    setState(() => _isLoading = false);
  }

  // ── GIỮ NGUYÊN 100% LOGIC BOTTOM SHEET ───────────────────────────────────
  void _showStageDetails(Map<String, dynamic> stage) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: _cardWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: _lineColor, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _orange.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.flag_circle_rounded, color: _orange, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Giai đoạn ${stage['day']}",
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _orange)),
                    Text(stage['title'],
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _darkText, height: 1.2)),
                  ]),
                ),
              ]),

              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.timer_outlined, size: 14, color: _midText),
                const SizedBox(width: 5),
                Text("Dự kiến: ${stage['estimated_time']}",
                    style: const TextStyle(color: _midText, fontSize: 13)),
              ]),

              const SizedBox(height: 18),
              Container(height: 1, color: _lineColor),
              const SizedBox(height: 18),

              const Text("Nhiệm vụ của bạn:",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _darkText)),
              const SizedBox(height: 12),

              ...List.generate(
                (stage['tasks'] as List).length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          color: _orange.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_right_rounded, color: _orange, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(stage['tasks'][i].toString(),
                            style: const TextStyle(fontSize: 14.5, color: _darkText, height: 1.5)),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context, stage); // GIỮ NGUYÊN: trả stage về màn hình trước
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: _cardWhite,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text("VÀO HỌC NGAY",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _orange))
                : _roadmapStages.isEmpty
                    ? const Center(child: Text("Không có dữ liệu lộ trình.", style: TextStyle(color: _midText)))
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  // ── APP BAR ───────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
        color: _bg,
        child: Row(children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _cardWhite,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: _orange.withOpacity(0.1), blurRadius: 8)],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: _darkText, size: 16),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: _orange.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.route_rounded, color: _orange, size: 20),
          ),
          const SizedBox(width: 10),
          const Text("Lộ trình học tập",
              style: TextStyle(color: _darkText, fontWeight: FontWeight.w800, fontSize: 17)),
          const Spacer(),
          IconButton(
            onPressed: _fetchRoadmap,
            icon: const Icon(Icons.refresh_rounded, color: _orange, size: 20),
            tooltip: "Tải lại",
          ),
        ]),
      ),
    );
  }

  // ── NỘI DUNG CHÍNH: hero + list ──────────────────────────────────────────
  Widget _buildContent() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960), // Rộng hơn bớt trống hai bên
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          itemCount: _roadmapStages.length + 1, // +1 cho hero
          itemBuilder: (context, index) {
            if (index == 0) return _buildHeroSection();

            final stageIndex = index - 1;
            final stage = _roadmapStages[stageIndex];

            // 🚀 GIỮ NGUYÊN THUẬT TOÁN KIỂM TRA MỞ KHÓA
            final bool isUnlocked = (stageIndex + 1) <= _currentStage;

            return _buildStageCard(stage, stageIndex, isUnlocked);
          },
        ),
      ),
    );
  }

  // ── HERO SECTION VỚI ẢNH ROAD ────────────────────────────────────────────
  Widget _buildHeroSection() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: _orange.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Ảnh road
            Image.asset(
              'assets/images/road.png',
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 200,
                color: _orange.withOpacity(0.1),
                child: const Center(child: Icon(Icons.route_rounded, size: 48, color: _orangeLight)),
              ),
            ),
            // Gradient overlay — đậm hơn ở trên để badge dễ đọc
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _orange.withOpacity(0.45),
                      Colors.transparent,
                      _orange.withOpacity(0.5),
                      _orange.withOpacity(0.88),
                    ],
                    stops: const [0.0, 0.3, 0.65, 1.0],
                  ),
                ),
              ),
            ),
            // Badge góc trên trái — nền đặc hơn để chữ rõ
            Positioned(
              top: 14, left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.directions_car_filled_rounded, color: _orange, size: 13),
                  const SizedBox(width: 5),
                  Text("Hành trình của bạn",
                      style: TextStyle(color: _orange, fontWeight: FontWeight.w800, fontSize: 11.5)),
                ]),
              ),
            ),
            // Chữ phía dưới
            Positioned(
              left: 16, right: 16, bottom: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  "Chinh Phục Từng Chặng",
                  style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900,
                    fontSize: 20, height: 1.2,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 8)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Hoàn thành Quiz mỗi giai đoạn để mở khóa chặng tiếp theo",
                  style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 12.5),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── CARD TỪNG GIAI ĐOẠN ──────────────────────────────────────────────────
  Widget _buildStageCard(Map<String, dynamic> stage, int index, bool isUnlocked) {
    return GestureDetector(
      onTap: () {
        // 🚀 GIỮ NGUYÊN LOGIC: chỉ cho tap nếu mở khóa
        if (isUnlocked) {
          _showStageDetails(stage);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              "🔒 Giai đoạn bị khóa! Bạn phải vượt qua bài Quiz của Giai đoạn ${index} trước."),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cột trái: circle + đường kẻ dọc ──────────────────────
            SizedBox(
              width: 56,
              child: Column(children: [
                // Circle icon
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isUnlocked ? _orange : _lineColor,
                    boxShadow: isUnlocked
                        ? [BoxShadow(color: _orange.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
                        : [],
                  ),
                  child: Icon(
                    isUnlocked ? Icons.play_arrow_rounded : Icons.lock_rounded,
                    color: isUnlocked ? Colors.white : _midText,
                    size: 26,
                  ),
                ),
                // Đường kẻ dọc nối các giai đoạn
                if (index < _roadmapStages.length - 1)
                  Container(
                    width: 2,
                    height: 40,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: isUnlocked ? _orange.withOpacity(0.3) : _lineColor,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ]),
            ),

            const SizedBox(width: 12),

            // ── Card nội dung ─────────────────────────────────────────
            Expanded(
              child: Container(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: isUnlocked ? _cardWhite : const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isUnlocked ? _orange.withOpacity(0.3) : _lineColor,
                    width: isUnlocked ? 1.5 : 1,
                  ),
                  boxShadow: isUnlocked
                      ? [BoxShadow(color: _orange.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))]
                      : [],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: label + badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Giai đoạn ${stage['day']}",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: isUnlocked ? _orange : _midText,
                            ),
                          ),
                          // 🚀 GIỮ NGUYÊN: badge ĐANG MỞ hoặc icon khóa
                          if (isUnlocked)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: const Text("ĐANG MỞ",
                                  style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w800)),
                            )
                          else
                            const Icon(Icons.lock_rounded, color: _midText, size: 15),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Tiêu đề giai đoạn
                      Text(
                        stage['title'],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isUnlocked ? _darkText : _midText,
                          height: 1.3,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Thời gian
                      Row(children: [
                        Icon(Icons.access_time_rounded,
                            size: 13, color: isUnlocked ? _orangeLight : _midText),
                        const SizedBox(width: 4),
                        Text(
                          stage['estimated_time'] ?? '',
                          style: TextStyle(
                              fontSize: 12,
                              color: isUnlocked ? _orangeLight : _midText,
                              fontWeight: FontWeight.w600),
                        ),
                      ]),

                      // 🚀 GIỮ NGUYÊN: dòng chữ đỏ yêu cầu khi bị khóa
                      if (!isUnlocked) ...[
                        const SizedBox(height: 10),
                        Container(height: 1, color: _lineColor),
                        const SizedBox(height: 10),
                        Row(children: [
                          const Icon(Icons.info_outline_rounded, size: 13, color: Colors.redAccent),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              "Yêu cầu: Đạt 80% bài Quiz của Giai đoạn ${index} để mở khóa",
                              style: const TextStyle(
                                  fontSize: 11.5, color: Colors.redAccent, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}