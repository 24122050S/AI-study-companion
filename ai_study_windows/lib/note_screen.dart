import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'api_constants.dart';

class NoteScreen extends StatefulWidget {
  final String username;
  final String notebookId;

  const NoteScreen({super.key, required this.username, required this.notebookId});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {

  List<dynamic> _notes = [];
  bool _isLoading = false;

  // ── Bảng màu: lấy cảm hứng từ giấy xanh dương của hình nền ───────────────
  static const Color _steelBlue   = Color(0xFF4A7BAF); // Xanh dương đậm chủ đạo
  static const Color _ruleBlue    = Color(0xFFB8D0E8); // Màu đường kẻ vở
  static const Color _marginRed   = Color(0xFFD94F4F); // Đường lề đỏ bên trái
  static const Color _paperWhite  = Color(0xFFF7FAFD); // Nền trang giấy
  static const Color _inkDark     = Color(0xFF2C3E50); // Màu mực chữ

  @override
  void initState() {
    super.initState();
    _fetchNotes();
  }

  // ═══════════════════════════════════════════════════════════
  //  GIỮ NGUYÊN TOÀN BỘ LOGIC GỐC
  // ═══════════════════════════════════════════════════════════

  Future<void> _fetchNotes() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse("${ApiConstants.baseUrl}/api/notes/${widget.username}/${widget.notebookId}"),
      );
      if (response.statusCode == 200) {
        setState(() {
          _notes = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải ghi chú: $e");
    }
    setState(() => _isLoading = false);
  }

  Future<void> _deleteNote(int noteId) async {
    try {
      final response = await http.delete(
        Uri.parse("${ApiConstants.baseUrl}/api/notes/$noteId"),
      );
      if (response.statusCode == 200) {
        _fetchNotes();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đã xóa khỏi sổ tay!"), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      debugPrint("Lỗi xóa ghi chú: $e");
    }
  }

  Future<void> _addNote(String title, String content) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: _steelBlue)),
    );

    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/notes"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username,
          "notebook_id": widget.notebookId,
          "title": title.isEmpty ? "Ghi chú mới" : title,
          "content": content,
        }),
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        _fetchNotes();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đã thêm ghi chú mới!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi kết nối máy chủ!"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editNote(int noteId, String newTitle, String newContent) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: _steelBlue)),
    );

    try {
      final response = await http.put(
        Uri.parse("${ApiConstants.baseUrl}/api/notes/$noteId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"title": newTitle, "content": newContent}),
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        _fetchNotes();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đã cập nhật ghi chú!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi kết nối máy chủ!"), backgroundColor: Colors.red),
      );
    }
  }

  void _showEditNoteDialog(int noteId, String currentTitle, String currentContent) {
    TextEditingController titleController   = TextEditingController(text: currentTitle);
    TextEditingController contentController = TextEditingController(text: currentContent);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _paperWhite,
        title: _dialogTitle("Chỉnh sửa ghi chú", Icons.edit_note),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _notebookTextField(controller: titleController, hint: "Tiêu đề", icon: Icons.title),
              const SizedBox(height: 14),
              _notebookTextField(controller: contentController, hint: "Nhập nội dung...", maxLines: 6),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Hủy", style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _steelBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              if (contentController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _editNote(noteId, titleController.text, contentController.text);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Nội dung không được để trống!"), backgroundColor: Colors.orange),
                );
              }
            },
            child: const Text("Lưu thay đổi", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddNoteDialog() {
    TextEditingController titleController   = TextEditingController();
    TextEditingController contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _paperWhite,
        title: _dialogTitle("Tạo ghi chú mới", Icons.add_circle_outline),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _notebookTextField(
                controller: titleController,
                hint: "Tiêu đề (Tùy chọn)",
                icon: Icons.title,
              ),
              const SizedBox(height: 14),
              _notebookTextField(
                controller: contentController,
                hint: "Nhập nội dung ghi chú của bạn vào đây...",
                maxLines: 6,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Hủy", style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _steelBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              if (contentController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _addNote(titleController.text, contentController.text);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Nội dung không được để trống!"), backgroundColor: Colors.orange),
                );
              }
            },
            child: const Text("Lưu ghi chú", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showReferenceTheory(String filename, int page) async {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: _steelBlue)),
    );

    try {
      final response = await http.get(
        Uri.parse(
          "${ApiConstants.baseUrl}/api/reference?user_id=${widget.username}&filename=$filename&page=$page&notebook_id=${widget.notebookId}",
        ),
      );

      if (!mounted) return;
      Navigator.pop(context);

      String theoryContent = "Lỗi không tải được dữ liệu.";
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        theoryContent = data['data'];
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: _paperWhite,
          title: Row(
            children: [
              const Icon(Icons.menu_book, color: Colors.indigo),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "$filename - Trang $page",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _ruleBlue),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)],
              ),
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: theoryContent,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                    tableBorder: TableBorder.all(color: Colors.grey.shade300, width: 1),
                    tableCellsPadding: const EdgeInsets.all(8),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Đã hiểu", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi kết nối máy chủ!")),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD CHÍNH
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories_rounded, color: _steelBlue, size: 22),
            const SizedBox(width: 10),
            const Text(
              "Sổ Tay Kiến Thức",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _steelBlue,
                fontSize: 18,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white.withOpacity(0.88),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _steelBlue),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(height: 2, color: _ruleBlue),
        ),
      ),
      body: Stack(
        children: [
          // Hình nền notebook
          Positioned.fill(
            child: Image.asset(
              'assets/images/notebook.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Overlay cho dễ đọc
          Positioned.fill(
            child: Container(color: Colors.white.withOpacity(0.22)),
          ),
          // Nội dung chính
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: _steelBlue,
                backgroundColor: _ruleBlue,
                strokeWidth: 3,
              ),
            )
          else if (_notes.isEmpty)
            _buildEmptyState()
          else
            _buildNotesList(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddNoteDialog,
        backgroundColor: _steelBlue,
        elevation: 3,
        icon: const Icon(Icons.edit, color: Colors.white, size: 20),
        label: const Text(
          "Ghi chú mới",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        tooltip: "Tạo ghi chú mới",
      ),
    );
  }

  // ── ĐÃ SỬA: Thu nhỏ trang giấy thông báo trống ───────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500), // <-- ĐIỂM CHỐT: Thu nhỏ bề ngang
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
              topLeft: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
            border: Border.all(color: _ruleBlue, width: 1),
            boxShadow: [
              BoxShadow(color: _steelBlue.withOpacity(0.15), blurRadius: 20, offset: const Offset(3, 6)),
            ],
          ),
          foregroundDecoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: _marginRed, width: 5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.import_contacts_rounded, size: 72, color: _steelBlue.withOpacity(0.30)),
              const SizedBox(height: 20),
              const Text(
                "Sổ tay của bạn đang trống!",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _steelBlue),
              ),
              const SizedBox(height: 8),
              Text(
                "Hãy bấm nút + để tự viết ghi chú\nhoặc lưu từ AI nhé.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ĐÃ SỬA: Thu nhỏ các tờ note và vẽ đầy đủ đường kẻ ─────────────────────
  Widget _buildNotesList() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800), // <-- ĐIỂM CHỐT: Thu nhỏ bề ngang các tờ note
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(
            20,
            kToolbarHeight + MediaQuery.of(context).padding.top + 30, // Đẩy xuống một xíu khỏi AppBar
            20,
            100,
          ),
          itemCount: _notes.length,
          itemBuilder: (context, index) {
            final note      = _notes[index];
            final String rawDate     = note['date'] ?? "";
            final String displayDate = rawDate.isNotEmpty ? rawDate.split('T')[0] : "Hôm nay";

            return Container(
              margin: const EdgeInsets.only(bottom: 26),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.96),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                  topLeft: Radius.circular(2),
                  bottomLeft: Radius.circular(2),
                ),
                border: Border.all(color: _ruleBlue, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: _steelBlue.withOpacity(0.12),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              foregroundDecoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: _marginRed, width: 4.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header: ngày + nút edit/delete ──────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0F6FB), // Xanh rất nhạt cho phần header
                    ),
                    foregroundDecoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _ruleBlue, width: 1.5),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 13, color: _steelBlue.withOpacity(0.6)),
                            const SizedBox(width: 6),
                            Text(
                              displayDate,
                              style: TextStyle(
                                fontSize: 13,
                                color: _steelBlue.withOpacity(0.8),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _actionButton(
                              icon: Icons.edit_outlined,
                              color: _steelBlue,
                              tooltip: "Sửa ghi chú",
                              onTap: () => _showEditNoteDialog(
                                note['id'],
                                note['title'] ?? "Ghi chú",
                                note['content'] ?? "",
                              ),
                            ),
                            const SizedBox(width: 8),
                            _actionButton(
                              icon: Icons.delete_outline,
                              color: Colors.redAccent,
                              tooltip: "Xóa ghi chú",
                              onTap: () => _deleteNote(note['id']),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Tiêu đề ghi chú ─────────────────────────────────────────
                  if (note['title'] != null && note['title'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 4),
                      child: Text(
                        note['title'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _steelBlue,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),

                  // ── ĐÃ SỬA: Ép khung chiều cao tối thiểu để luôn vẽ dòng kẻ ─
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 180), // <-- ĐIỂM CHỐT: Luôn vẽ đủ kẻ dòng
                      child: CustomPaint(
                        painter: _RuledLinePainter(lineColor: _ruleBlue.withOpacity(0.60)),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: MarkdownBody(
                            data: note['content'] ?? "",
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(fontSize: 15, height: 1.73, color: _inkDark),
                              a: const TextStyle(
                                color: Colors.indigo,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            onTapLink: (text, href, title) {
                              if (href != null && href.startsWith('http://ref/')) {
                                String cleanHref = Uri.decodeComponent(
                                  href.replaceAll('http://ref/', '').trim(),
                                );
                                final parts = cleanHref.split('|');
                                if (parts.length == 2) {
                                  String filename = parts[0];
                                  int page = int.tryParse(parts[1]) ?? 1;
                                  _showReferenceTheory(filename, page);
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  Widget _dialogTitle(String text, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, color: _steelBlue, size: 22),
            const SizedBox(width: 10),
            Text(
              text,
              style: const TextStyle(
                color: _steelBlue,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 1.5, color: _ruleBlue),
      ],
    );
  }

  Widget _notebookTextField({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: _inkDark, fontSize: 14, height: 1.6),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _steelBlue.withOpacity(0.45)),
        prefixIcon: icon != null ? Icon(icon, color: _steelBlue, size: 20) : null,
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _ruleBlue, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _steelBlue, width: 2),
        ),
      ),
    );
  }
}

class _RuledLinePainter extends CustomPainter {
  final Color lineColor;
  const _RuledLinePainter({required this.lineColor});

  static const double _lineSpacing = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.8;

    double y = _lineSpacing;
    while (y < size.height + _lineSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += _lineSpacing;
    }
  }

  @override
  bool shouldRepaint(covariant _RuledLinePainter old) => old.lineColor != lineColor;
}