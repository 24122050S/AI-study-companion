import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';

// ============================================================
//  FILE THAY THẾ: ai_study_windows/lib/concept_map_screen.dart
//  🚀 MỚI: Ấn vào node -> Bottom sheet giải thích khái niệm (RAG)
//
//  HƯỚNG DẪN THIẾT LẬP HÌNH NỀN
//  1. Sao chép file mind_map.jpg vào thư mục: assets/images/
//  2. Thêm vào pubspec.yaml:
//     flutter:
//       assets:
//         - assets/images/mind_map.jpg
// ============================================================

class ConceptMapScreen extends StatefulWidget {
  final String username;
  final String notebookId;

  const ConceptMapScreen(
      {super.key, required this.username, required this.notebookId});

  @override
  State<ConceptMapScreen> createState() => _ConceptMapScreenState();
}

class _ConceptMapScreenState extends State<ConceptMapScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String _errorMessage = "";

  final Graph _graph = Graph()..isTree = true;
  final BuchheimWalkerConfiguration _builder = BuchheimWalkerConfiguration();

  List<dynamic> _nodesData = [];
  final Set<String> _childNodeIds = {}; // Dùng để phân biệt node gốc & node con

  // 🚀 MỚI: Cache giải thích — ấn lại cùng 1 node sẽ không gọi lại API
  final Map<String, String> _explainCache = {};

  // ── Bảng màu: lấy cảm hứng từ doodle yellow & ink black ──────────────────
  static const Color _inkBlack = Color(0xFF1C1C1E);
  static const Color _doodleYellow = Color(0xFFFFD600);
  static const Color _paperWhite = Color(0xFFFFFDF5);

  // Bảng màu đậm cho node con — xen kẽ theo index để dễ phân biệt
  static const List<Color> _nodeColors = [
    Color(0xFF1B3A6B), // Navy đậm
    Color(0xFF0D5C63), // Teal đậm
    Color(0xFF6B2D6B), // Tím đậm
    Color(0xFF8B2500), // Cam cháy
    Color(0xFF1A5C3A), // Xanh lá đậm
    Color(0xFF4A1A6B), // Indigo đậm
  ];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _builder
      ..siblingSeparation = 60
      ..levelSeparation = 130
      ..subtreeSeparation = 80
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM;

    // Hoạt ảnh nhịp đập cho loading indicator
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim =
        Tween<double>(begin: 0.85, end: 1.0).animate(_pulseController);

    _fetchConceptMap();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchConceptMap() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
      _childNodeIds.clear();
      _explainCache.clear(); // 🚀 MỚI: sơ đồ mới -> xóa cache giải thích cũ
      // Xóa graph cũ trước khi vẽ lại
      for (final node in List.from(_graph.nodes)) {
        _graph.removeNode(node);
      }
    });

    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/concept_map"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(
            {"user_id": widget.username, "notebook_id": widget.notebookId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        if (data['status'] == 'success') {
          _nodesData = data['data']['nodes'];
          List<dynamic> edgesData = data['data']['edges'];

          Map<String, Node> nodeMap = {};

          // 1. Tạo các Đỉnh (Nodes)
          for (var n in _nodesData) {
            var node = Node.Id(n['id'].toString());
            nodeMap[n['id'].toString()] = node;
            _graph.addNode(node);
          }

          // 2. Nối các Đỉnh (Edges) & ghi nhận node con
          for (var e in edgesData) {
            var fromNode = nodeMap[e['from'].toString()];
            var toNode = nodeMap[e['to'].toString()];
            if (fromNode != null && toNode != null) {
              _graph.addEdge(fromNode, toNode);
              _childNodeIds.add(e['to'].toString()); // đánh dấu node con
            }
          }
        } else {
          _errorMessage = data['message'] ?? "Lỗi không xác định";
        }
      } else {
        _errorMessage = "Máy chủ trả về lỗi: ${response.statusCode}";
      }
    } catch (e) {
      _errorMessage = "Lỗi kết nối: $e";
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 🚀 MỚI: GỌI API RAG GIẢI THÍCH KHÁI NIỆM CỦA NODE
  // ════════════════════════════════════════════════════════════════════════
  Future<String> _fetchNodeExplanation(String label) async {
    if (_explainCache.containsKey(label)) return _explainCache[label]!;

    final response = await http.post(
      Uri.parse("${ApiConstants.baseUrl}/api/concept_map/explain"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "user_id": widget.username,
        "notebook_id": widget.notebookId,
        "concept": label,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['status'] == 'success') {
        final String text =
            (data['data']?['explanation'] ?? "Không có nội dung.").toString();
        _explainCache[label] = text; // chỉ cache khi thành công
        return text;
      }
      throw Exception(data['message'] ?? "Lỗi không xác định");
    }
    throw Exception("Máy chủ trả về lỗi: ${response.statusCode}");
  }

  // ════════════════════════════════════════════════════════════════════════
  // 🚀 MỚI: BOTTOM SHEET HIỂN THỊ GIẢI THÍCH (PHONG CÁCH DOODLE)
  // ════════════════════════════════════════════════════════════════════════
  void _showNodeExplanation(String label) {
    // Tạo Future MỘT LẦN ở đây để kéo/thả bottom sheet không gọi lại API
    final Future<String> explanationFuture = _fetchNodeExplanation(label);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: _paperWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _inkBlack, width: 3),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thanh kéo
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: _inkBlack.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Tiêu đề = tên khái niệm (thẻ vàng doodle)
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _doodleYellow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _inkBlack, width: 2.5),
                        boxShadow: const [
                          BoxShadow(
                            color: _inkBlack,
                            blurRadius: 0,
                            offset: Offset(3, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: _inkBlack,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Nội dung giải thích lấy từ RAG
              Expanded(
                child: FutureBuilder<String>(
                  future: explanationFuture,
                  builder: (context, snapshot) {
                    // Đang tra cứu tài liệu
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 38,
                              height: 38,
                              child: CircularProgressIndicator(
                                color: _inkBlack,
                                strokeWidth: 3.5,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            SizedBox(height: 14),
                            Text(
                              "AI đang tra cứu tài liệu của bạn...",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _inkBlack,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Có lỗi
                    if (snapshot.hasError) {
                      final msg = snapshot.error
                          .toString()
                          .replaceFirst("Exception: ", "");
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Colors.redAccent, size: 34),
                            const SizedBox(height: 10),
                            Text(
                              msg,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Hiển thị giải thích
                    return SingleChildScrollView(
                      controller: scrollCtrl,
                      child: Text(
                        snapshot.data ?? "Không có nội dung.",
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.65,
                          color: _inkBlack,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Khối thiết kế Node ────────────────────────────────────────────────────
  Widget _buildNodeWidget(Node node) {
    final String nodeId = node.key!.value.toString();
    final nodeData = _nodesData.firstWhere(
      (n) => n['id'].toString() == nodeId,
      orElse: () => {"label": "?"},
    );

    final bool isRoot = !_childNodeIds.contains(nodeId);
    final String label = (nodeData['label'] ?? "?").toString();
    const Color nodeColor = Color(0xFF1B3A6B); // Navy đậm

    Widget bubble;

    if (isRoot) {
      // ══ Node gốc: phong cách "IDEAS" - vàng nổi bật với bóng mực ══
      bubble = Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        constraints: const BoxConstraints(maxWidth: 210),
        decoration: BoxDecoration(
          color: _doodleYellow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _inkBlack, width: 3),
          // Bóng đổ phẳng kiểu comic/doodle (blurRadius = 0)
          boxShadow: const [
            BoxShadow(
              color: _inkBlack,
              blurRadius: 0,
              offset: Offset(5, 5),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: _inkBlack,
            fontSize: 15,
            letterSpacing: 0.4,
            height: 1.35,
          ),
        ),
      );
    } else {
      // ══ Node con: màu đậm tương phản mạnh, chữ trắng ══
      bubble = Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        constraints: const BoxConstraints(maxWidth: 175),
        decoration: BoxDecoration(
          color: nodeColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
          // Bóng đổ doodle — offset phẳng không blur
          boxShadow: [
            BoxShadow(
              color: _inkBlack.withOpacity(0.60),
              blurRadius: 0,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      );
    }

    // 🚀 MỚI: Ấn vào node -> mở bottom sheet giải thích khái niệm bằng RAG
    return GestureDetector(
      onTap: () => _showNodeExplanation(label),
      child: bubble,
    );
  }

  // ── Widget loading có hoạt ảnh nhịp đập ──────────────────────────────────
  Widget _buildLoadingCard() {
    return Center(
      child: ScaleTransition(
        scale: _pulseAnim,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
          decoration: BoxDecoration(
            color: _paperWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _inkBlack, width: 3),
            boxShadow: const [
              BoxShadow(
                color: _inkBlack,
                blurRadius: 0,
                offset: Offset(6, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vòng tròn loading với màu vàng doodle
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: _doodleYellow,
                  backgroundColor: _inkBlack.withOpacity(0.12),
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                ),
              ),
              const SizedBox(height: 18),
              // Dấu chấm động (...)
              const _DotLoadingText(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget thông báo lỗi ─────────────────────────────────────────────────
  Widget _buildErrorCard() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _paperWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.shade400, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.redAccent.shade400,
              blurRadius: 0,
              offset: const Offset(5, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: Colors.redAccent, size: 36),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _fetchConceptMap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _doodleYellow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _inkBlack, width: 2),
                  boxShadow: const [
                    BoxShadow(
                        color: _inkBlack, blurRadius: 0, offset: Offset(3, 3))
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, size: 16, color: _inkBlack),
                    SizedBox(width: 6),
                    Text(
                      "Thử lại",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: _inkBlack),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Để nền hiện ra phía sau AppBar
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // ── AppBar: giấy trắng ngà, viền mực nhẹ ──
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dấu chấm vàng trang trí
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _doodleYellow,
                shape: BoxShape.circle,
                border: Border.all(color: _inkBlack, width: 1.5),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              "Sơ đồ Tư duy (AI Map)",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _inkBlack,
                fontSize: 17,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        backgroundColor: _paperWhite.withOpacity(0.90),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _inkBlack),
        // Đường viền mực mỏng dưới AppBar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
            color: _inkBlack.withOpacity(0.12),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GestureDetector(
              onTap: _fetchConceptMap,
              child: Tooltip(
                message: "Tạo sơ đồ mới",
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _doodleYellow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _inkBlack, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: _inkBlack,
                        blurRadius: 0,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_fix_high_rounded,
                          color: _inkBlack, size: 16),
                      SizedBox(width: 5),
                      Text(
                        "Tạo mới",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _inkBlack,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      body: Stack(
        children: [
          // ── Lớp 1: Hình nền doodle ────────────────────────────────────────
          Positioned.fill(
            child: Image.asset(
              'assets/images/mind_map.jpg',
              fit: BoxFit.cover,
            ),
          ),

          // ── Lớp 2: Lớp phủ trắng nhẹ để nodes nổi bật hơn ───────────────
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.30),
            ),
          ),

          // ── Lớp 3: Nội dung ───────────────────────────────────────────────
          if (_isLoading)
            _buildLoadingCard()
          else if (_errorMessage.isNotEmpty)
            _buildErrorCard()
          else
            InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(300),
              minScale: 0.1,
              maxScale: 3.5,
              child: Padding(
                // Padding top lớn để tránh AppBar che mất node
                padding: EdgeInsets.fromLTRB(
                  60,
                  kToolbarHeight + MediaQuery.of(context).padding.top + 30,
                  60,
                  60,
                ),
                child: GraphView(
                  graph: _graph,
                  algorithm: BuchheimWalkerAlgorithm(
                    _builder,
                    TreeEdgeRenderer(_builder),
                  ),
                  // Đường nối: mực đen, nét vừa
                  paint: Paint()
                    ..color = _inkBlack.withOpacity(0.55)
                    ..strokeWidth = 2.5
                    ..style = PaintingStyle.stroke
                    ..strokeCap = StrokeCap.round,
                  builder: (Node node) => _buildNodeWidget(node),
                ),
              ),
            ),

          // ── 🚀 MỚI: Lớp 4 — Gợi ý "Ấn vào node để xem giải thích" ─────────
          if (!_isLoading && _errorMessage.isEmpty)
            Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _paperWhite.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _inkBlack, width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: _inkBlack, blurRadius: 0, offset: Offset(3, 3))
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_rounded,
                          size: 16, color: _inkBlack),
                      SizedBox(width: 6),
                      Text(
                        "Ấn vào một node để xem giải thích khái niệm",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _inkBlack,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Widget chấm loading động "AI đang vẽ..." ─────────────────────────────────
class _DotLoadingText extends StatefulWidget {
  const _DotLoadingText();

  @override
  State<_DotLoadingText> createState() => _DotLoadingTextState();
}

class _DotLoadingTextState extends State<_DotLoadingText> {
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(milliseconds: 480), () {
      if (mounted) {
        setState(() => _dotCount = (_dotCount + 1) % 4);
        _tick();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * _dotCount;
    return Text(
      "AI đang vẽ Sơ đồ tư duy$dots",
      style: const TextStyle(
        color: _ConceptMapScreenState._inkBlack,
        fontWeight: FontWeight.bold,
        fontSize: 14,
        letterSpacing: 0.3,
      ),
    );
  }
}
