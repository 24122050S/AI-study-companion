import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';

class FileHistoryScreen extends StatefulWidget {
  final String username;
  const FileHistoryScreen({super.key, required this.username});

  @override
  State<FileHistoryScreen> createState() => _FileHistoryScreenState();
}

class _FileHistoryScreenState extends State<FileHistoryScreen> {
  
  List<dynamic> _files = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  // Tải danh sách file
  Future<void> _fetchFiles() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/files/${widget.username}"));
      if (response.statusCode == 200) {
        setState(() => _files = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print("Lỗi tải lịch sử file: $e");
    }
    setState(() => _isLoading = false);
  }

  // Xóa 1 file
  Future<void> _deleteFile(int fileId) async {
    try {
      final response = await http.delete(Uri.parse("${ApiConstants.baseUrl}/api/files/$fileId"));
      if (response.statusCode == 200) {
        _fetchFiles(); // Tải lại danh sách
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa khỏi danh sách!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.grey));
      }
    } catch (e) {
      print("Lỗi xóa file: $e");
    }
  }

  // Tẩy não AI
  Future<void> _resetBrain() async {
    // Hiện bảng hỏi xác nhận cho chắc cú
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(children: [Icon(Icons.warning, color: Colors.red), SizedBox(width: 10), Text("Cảnh báo!")]),
        content: const Text("Hành động này sẽ xóa sạch trí nhớ của AI và toàn bộ tài liệu đã học. Bạn có chắc chắn muốn Tẩy não AI để học từ đầu không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Tẩy Não Ngay", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        final response = await http.delete(Uri.parse("${ApiConstants.baseUrl}/api/files/reset/${widget.username}"));
        if (response.statusCode == 200) {
          _fetchFiles();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ AI đã bị tẩy não. Giờ bạn có thể tải tài liệu mới!'), backgroundColor: Colors.green));
        }
      } catch (e) {
        print("Lỗi tẩy não: $e");
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Kho tài liệu", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.brown,
        actions: [
          // NÚT TẨY NÃO AI TRÊN GÓC PHẢI
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white, size: 28),
            tooltip: "Tẩy não AI (Làm mới)",
            onPressed: _files.isEmpty ? null : _resetBrain,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.brown))
          : _files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 10),
                      const Text("Chưa có tài liệu nào.", style: TextStyle(fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final f = _files[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 35),
                        title: Text(f['filename'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Ngày tải: ${f['date']}"),
                        // NÚT XÓA TỪNG FILE
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteFile(f['id']),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}