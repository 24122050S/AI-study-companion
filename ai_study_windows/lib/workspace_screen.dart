import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'home_screen.dart'; // Màn hình chat hiện tại của bạn

class WorkspaceScreen extends StatefulWidget {
  final String username;
  const WorkspaceScreen({super.key, required this.username});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final String apiUrl = "http://localhost:8000";
  List<dynamic> _notebooks = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchNotebooks();
  }

  Future<void> _fetchNotebooks() async {
    setState(() => _isLoading = true);
    final res = await http.get(Uri.parse("$apiUrl/api/notebooks/${widget.username}"));
    if (res.statusCode == 200) {
      setState(() => _notebooks = jsonDecode(utf8.decode(res.bodyBytes)));
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createNotebook(String title) async {
    await http.post(
      Uri.parse("$apiUrl/api/notebooks"),
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

  Widget _buildNotebookCard(dynamic nb) {
    return InkWell(
      onTap: () {
        // Chuyển vào HomeScreen nhưng truyền thêm notebook_id
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => HomeScreen(notebookId: nb['id'].toString(), notebookTitle: nb['title'])
        ));
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.book, color: Colors.orange, size: 30),
              const Spacer(),
              Text(nb['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text("Ngày tạo: ${nb['created_at'].toString().split('T')[0]}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
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
}