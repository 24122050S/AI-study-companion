import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'home_screen.dart'; 
import 'api_constants.dart';

class WorkspaceScreen extends StatefulWidget {
  final String username;
  const WorkspaceScreen({super.key, required this.username});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  List<dynamic> _notebooks = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchNotebooks();
  }

  Future<void> _fetchNotebooks() async {
    setState(() => _isLoading = true);
    final res = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/notebooks/${widget.username}"));
    if (res.statusCode == 200) {
      setState(() => _notebooks = jsonDecode(utf8.decode(res.bodyBytes)));
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createNotebook(String title) async {
    await http.post(
      Uri.parse("${ApiConstants.baseUrl}/api/notebooks"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"user_id": widget.username, "title": title}),
    );
    _fetchNotebooks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("My Notebooks", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0,
        actions: [
          CircleAvatar(backgroundColor: Colors.blue, child: Text(widget.username[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
          const SizedBox(width: 20),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Chào mừng trở lại!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Chọn một dự án để tiếp tục nghiên cứu", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, crossAxisSpacing: 20, mainAxisSpacing: 20, childAspectRatio: 1.5
                    ),
                    itemCount: _notebooks.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return _buildCreateCard();
                      final nb = _notebooks[index - 1];
                      return _buildNotebookCard(nb);
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateCard() {
    return InkWell(
      onTap: () => _showCreateDialog(),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.blue.withOpacity(0.5), width: 2, style: BorderStyle.none)
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 50, color: Colors.blue),
            SizedBox(height: 10),
            Text("Tạo Notebook mới", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // 1. ĐÃ SỬA: Hàm vẽ Card dự án được bọc trong Stack để chứa nút 3 chấm
  Widget _buildNotebookCard(dynamic nb) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Stack(
        children: [
          // Khu vực bấm mở dự án
          InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => HomeScreen(notebookId: nb['id'].toString(), notebookTitle: nb['title'])
              ));
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.bookmark, color: Colors.orange, size: 30),
                  const Spacer(),
                  Text(nb['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text("Ngày tạo: ${nb['created_at'].toString().split('T')[0]}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
          
          // Nút 3 chấm ghim góc phải
          Positioned(
            top: 8,
            right: 8,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onSelected: (value) {
                if (value == 'delete') {
                  _showDeleteDialog(nb['id'], nb['title']);
                } else if (value == 'rename') {
                  // Gọi hàm đổi tên khi bấm
                  _showRenameDialog(nb['id'], nb['title']); 
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Text('Đổi tên', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Xóa dự án', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog() {
    TextEditingController _control = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Tên Notebook mới"),
        content: TextField(controller: _control, decoration: const InputDecoration(hintText: "Ví dụ: Lịch sử Đảng, Vi điều khiển...")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(onPressed: () {
            _createNotebook(_control.text);
            Navigator.pop(context);
          }, child: const Text("Tạo ngay")),
        ],
      ),
    );
  }

  // 2. THÊM MỚI: Popup cảnh báo xác nhận xóa
  void _showDeleteDialog(int notebookId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 10),
            Text("Xóa dự án $title?"),
          ],
        ),
        content: const Text(
          "Hành động này không thể hoàn tác! Toàn bộ file tài liệu, lịch sử chat và các bộ đề trắc nghiệm thuộc dự án này sẽ bị xóa sạch.",
          style: TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hủy bỏ", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context); 
              _executeDeleteNotebook(notebookId); 
            },
            child: const Text("Xóa vĩnh viễn", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 3. THÊM MỚI: Hàm gọi API xóa và tải lại danh sách
  Future<void> _executeDeleteNotebook(int notebookId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.red)),
    );

    try {
      final response = await http.delete(
        Uri.parse("${ApiConstants.baseUrl}/api/notebooks/$notebookId"),
      );

      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(responseData['message'] ?? "Đã xóa dự án thành công!"), backgroundColor: Colors.green),
        );
        _fetchNotebooks(); // Cập nhật lại màn hình ngay lập tức
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Không thể xóa dự án từ máy chủ."), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi kết nối máy chủ."), backgroundColor: Colors.red),
      );
    }
  }
  // Hàm 1: Hiển thị hộp thoại nhập tên mới
  void _showRenameDialog(int notebookId, String currentTitle) {
    TextEditingController _control = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Đổi tên Dự án"),
        content: TextField(
          controller: _control, 
          autofocus: true, // Tự động bật bàn phím khi mở
          decoration: const InputDecoration(
            hintText: "Nhập tên mới...",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("Hủy", style: TextStyle(color: Colors.grey))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () {
              Navigator.pop(context);
              _executeRenameNotebook(notebookId, _control.text);
            }, 
            child: const Text("Lưu thay đổi", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }

  // Hàm 2: Gọi API lưu tên mới lên Python
  Future<void> _executeRenameNotebook(int notebookId, String newTitle) async {
    if (newTitle.trim().isEmpty) return; // Tránh đổi thành tên rỗng
    
    // Bật vòng xoay loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http.put(
        Uri.parse("${ApiConstants.baseUrl}/api/notebooks/$notebookId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"title": newTitle.trim()}),
      );

      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (response.statusCode == 200) {
        _fetchNotebooks(); // Tải lại danh sách dự án
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đã đổi tên thành công!"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi kết nối máy chủ!"), backgroundColor: Colors.red)
      );
    }
  }
}