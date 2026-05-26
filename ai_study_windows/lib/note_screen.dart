import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'api_constants.dart';

class NoteScreen extends StatefulWidget {
  final String username;
  final String notebookId; // Quản lý theo cấu trúc dự án

  const NoteScreen({super.key, required this.username, required this.notebookId});

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

  // LẤY DANH SÁCH GHI CHÚ
  Future<void> _fetchNotes() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/notes/${widget.username}/${widget.notebookId}"));
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

  // XÓA GHI CHÚ
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

  // TẠO GHI CHÚ MỚI BẰNG TAY BÊN TRONG SỔ TAY
  Future<void> _addNote(String title, String content) async {
    // Hiện vòng xoay loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.teal)),
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
      Navigator.pop(context); // Tắt loading

      if (response.statusCode == 200) {
        _fetchNotes(); // Tải lại danh sách
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
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.teal)),
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
        _fetchNotes(); // Tải lại danh sách
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

  // --- HÀM HIỂN THỊ POPUP NHẬP LẠI NỘI DUNG ---
  void _showEditNoteDialog(int noteId, String currentTitle, String currentContent) {
    TextEditingController titleController = TextEditingController(text: currentTitle);
    TextEditingController contentController = TextEditingController(text: currentContent);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Chỉnh sửa ghi chú", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  hintText: "Tiêu đề",
                  prefixIcon: Icon(Icons.title, color: Colors.teal),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: contentController,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: "Nhập nội dung...",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.teal, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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

  // GIAO DIỆN HIỂN THỊ POPUP VIẾT GHI CHÚ MỚI
  void _showAddNoteDialog() {
    TextEditingController titleController = TextEditingController();
    TextEditingController contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Tạo ghi chú mới", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  hintText: "Tiêu đề (Tùy chọn)",
                  prefixIcon: Icon(Icons.title, color: Colors.teal),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: contentController,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: "Nhập nội dung ghi chú của bạn vào đây...",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.teal, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              if (contentController.text.trim().isNotEmpty) {
                Navigator.pop(context); // Đóng popup
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

  // ================= HIỂN THỊ LÝ THUYẾT GỐC =================
  Future<void> _showReferenceTheory(String filename, int page) async {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.indigo)),
    );

    try {
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
      // 👇 NÚT THÊM GHI CHÚ NẰM Ở GÓC DƯỚI BÊN PHẢI MÀN HÌNH
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNoteDialog,
        backgroundColor: Colors.teal,
        tooltip: "Tạo ghi chú mới",
        child: const Icon(Icons.add, color: Colors.white),
      ),
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
          const Text("Hãy bấm nút + để tự viết ghi chú hoặc lưu từ AI nhé.", style: TextStyle(color: Colors.grey)),
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
                        // Nút chỉnh sửa
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                          onPressed: () => _showEditNoteDialog(
                            note['id'], 
                            note['title'] ?? "Ghi chú", 
                            note['content'] ?? ""
                          ),
                          tooltip: "Sửa ghi chú",
                        ),
                        // Nút xóa cũ
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _deleteNote(note['id']),
                          tooltip: "Xóa ghi chú",
                        )
                      ],
                    )
                  ],
                ),
              ),
              
              if (note['title'] != null && note['title'].toString().isNotEmpty && note['title'] != 'Ghi chú mới')
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 15),
                  child: Text(
                    note['title'],
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
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