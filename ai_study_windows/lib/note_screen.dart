import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'api_constants.dart';

class NoteScreen extends StatefulWidget {
  final String username;
  final String notebookId; // 👈 THÊM: Quản lý theo cấu trúc dự án

  const NoteScreen({
    super.key, 
    required this.username,
    required this.notebookId, // 👈 BẮT BUỘC NHẬN VÀO KHỞI TẠO
  });

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  
  List<dynamic> _notes = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchNotes();
  }

  Future<void> _fetchNotes() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/notes/${widget.username}"));
      if (response.statusCode == 200) {
        setState(() {
          _notes = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      print("Lỗi tải ghi chú: $e");
    }
    setState(() => _isLoading = false);
  }

  Future<void> _deleteNote(int noteId) async {
    try {
      final response = await http.delete(Uri.parse("${ApiConstants.baseUrl}/api/notes/$noteId"));
      if (response.statusCode == 200) {
        _fetchNotes();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đã xóa khỏi sổ tay!"), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      print("Lỗi xóa ghi chú: $e");
    }
  }

  // ================= HIỂN THỊ LÝ THUYẾT GỐC (ĐÃ SỬA LỖI ĐỒNG BỘ NOTEBOOK ID) =================
  Future<void> _showReferenceTheory(String filename, int page) async {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.indigo)),
    );

    try {
      // 👇 NÂNG CẤP: ĐÍNH KÈM THÊM NOTEBOOK ID VÀO ĐUÔI LINK GET REQUEST
      final response = await http.get(
        Uri.parse("${ApiConstants.baseUrl}/api/reference?user_id=${widget.username}&filename=$filename&page=$page&notebook_id=${widget.notebookId}"),
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
          backgroundColor: const Color(0xFFFAFAFA),
          title: Row(
            children: [
              const Icon(Icons.menu_book, color: Colors.indigo),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "$filename - Trang $page", 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
                  overflow: TextOverflow.ellipsis,
                )
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
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)]
              ),
              child: SingleChildScrollView(
                // 👇 THAY THẺ TEXT THÀNH MARKDOWN BODY ĐỂ HIỂN THỊ BẢNG VÀ CHỮ IN ĐẬM
                child: MarkdownBody(
                  data: theoryContent,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                    // Có thể thêm style cho bảng nếu muốn
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text("Đã hiểu", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi kết nối máy chủ!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8), 
      appBar: AppBar(
        title: const Text("Sổ Tay Kiến Thức", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.teal,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : _notes.isEmpty
              ? _buildEmptyState()
              : _buildNotesList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.import_contacts, size: 100, color: Colors.teal.withOpacity(0.3)),
          const SizedBox(height: 20),
          const Text("Sổ tay của bạn đang trống!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 10),
          const Text("Hãy chat với AI và nhấn nút Lưu để ghi nhớ kiến thức nhé.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildNotesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        final String rawDate = note['date'] ?? "";
        final String displayDate = rawDate.isNotEmpty ? rawDate.split('T')[0] : "Hôm nay";

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
            border: Border.all(color: Colors.grey.shade100)
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 16, color: Colors.teal),
                        const SizedBox(width: 8),
                        Text(displayDate, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _deleteNote(note['id']),
                      tooltip: "Xóa ghi chú",
                    )
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(20),
                child: MarkdownBody(
                  data: note['content'],
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                    a: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                  ),
                  // BẮT CÚ CLICK CHUỘT VỚI LINK MÃ HÓA GIẢ HTTP://REF/
                  onTapLink: (text, href, title) {
                    if (href != null && href.startsWith('http://ref/')) {
                      String cleanHref = Uri.decodeComponent(href.replaceAll('http://ref/', '').trim());
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
            ],
          ),
        );
      },
    );
  }
}