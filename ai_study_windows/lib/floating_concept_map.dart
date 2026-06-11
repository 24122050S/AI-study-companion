import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';
import 'quiz_screen.dart';

class FloatingConceptMap extends StatefulWidget {
  final String notebookId;
  final String username;

  const FloatingConceptMap({
    super.key,
    required this.notebookId,
    required this.username,
  });

  @override
  State<FloatingConceptMap> createState() => _FloatingConceptMapState();
}

class _FloatingConceptMapState extends State<FloatingConceptMap> {
  bool _isMinimized = true;
  bool _isLoading = false;
  List<dynamic> _nodes = [];
  
  // Tọa độ vị trí hiển thị ban đầu trên màn hình
  double _posX = 20.0;
  double _posY = 120.0;

  @override
  void initState() {
    super.initState();
    _loadConceptMap();
  }

  // Tải danh sách node sơ đồ tư duy từ Backend
  Future<void> _loadConceptMap() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/concept_map"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username,
          "notebook_id": widget.notebookId,
        }),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded['status'] == 'success') {
          setState(() {
            _nodes = decoded['data']['nodes'] ?? [];
          });
        }
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  // Kích hoạt bài kiểm tra cấp tốc khi ấn vào từng Node kiến thức
  void _triggerAiQuestion(String conceptName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20.0), // Đã sửa: đưa padding vào trong Widget hợp lệ
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF6DBFAB)),
                SizedBox(width: 15),
                Text(
                  "AI đang chuẩn bị câu hỏi thử thách...", 
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/quiz"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username,
          "notebook_id": widget.notebookId,
          "num_questions": 3, 
          "difficulty": "Trung bình",
          "quiz_type": "Trộn lẫn",
          "focus_topic": conceptName
        }),
      );

      if (!mounted) return;
      Navigator.pop(context); // Đóng Dialog Loading

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final preloadedQuestions = decoded['data'] ?? [];

        // Điều hướng mượt mà sang phòng thi mới tập trung vào chủ đề đã ấn
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => QuizScreen(
              modeName: "Thử thách: $conceptName",
              numQuestions: preloadedQuestions.length,
              timeLimit: 0,
              username: widget.username,
              notebookId: widget.notebookId,
              preloadedQuestions: preloadedQuestions,
              focusTopic: conceptName,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _posX,
      top: _posY,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _posX += details.delta.dx;
            _posY += details.delta.dy;
          });
        },
        child: _isMinimized ? _buildMinimizedUI() : _buildExpandedUI(),
      ),
    );
  }

  // UI khi thu nhỏ thành bong bóng tròn nổi
  Widget _buildMinimizedUI() {
    return FloatingActionButton(
      heroTag: "concept_map_fab",
      backgroundColor: const Color(0xFF1D3330),
      elevation: 8,
      onPressed: () {
        setState(() {
          _isMinimized = false;
        });
      },
      child: const Icon(Icons.hub_rounded, color: Color(0xFFFFCC5C), size: 26),
    );
  }

  // UI khi phóng to cửa sổ danh sách bài học
  Widget _buildExpandedUI() {
    return Container(
      width: 280,
      constraints: const BoxConstraints(maxHeight: 350), // Đã sửa: bọc maxHeight vào BoxConstraints hợp lệ
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6DBFAB), width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thanh tiêu đề điều hướng cửa sổ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF0FAF7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.hub, size: 16, color: Color(0xFF4A9E8C)),
                const SizedBox(width: 6),
                const Text(
                  "Sơ đồ tư duy AI", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1D3330)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFFE8604A)),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    setState(() {
                      _isMinimized = true;
                    });
                  },
                )
              ],
            ),
          ),
          
          // Danh sách các khối kiến thức
          Flexible(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(color: Color(0xFF6DBFAB)),
                  )
                : _nodes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text("Chưa có sơ đồ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(10),
                        itemCount: _nodes.length,
                        itemBuilder: (context, index) {
                          final node = _nodes[index];
                          final String label = node['label'] ?? "Khái niệm";
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF5957F).withOpacity(0.15),
                                foregroundColor: const Color(0xFF1D3330),
                                elevation: 0,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: Color(0xFFF5957F), width: 1)
                                )
                              ),
                              onPressed: () => _triggerAiQuestion(label),
                              child: Row(
                                children: [
                                  const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFFFCC5C)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      label, 
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}