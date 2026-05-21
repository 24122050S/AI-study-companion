import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class NoteScreen extends StatefulWidget {
  final String username;
  const NoteScreen({super.key, required this.username});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  final String apiUrl = "http://10.0.195.105:8000";
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
      final response = await http.get(Uri.parse("$apiUrl/api/notes/${widget.username}"));
      if (response.statusCode == 200) {
        setState(() => _notes = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print("Lỗi tải ghi chú: $e");
    }
    setState(() => _isLoading = false);
  }

  void _showAddNoteDialog() {
    TextEditingController titleController = TextEditingController();
    TextEditingController contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Thêm ghi chú mới"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: "Tiêu đề")),
            TextField(controller: contentController, maxLines: 3, decoration: const InputDecoration(labelText: "Nội dung")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              await http.post(
                Uri.parse("$apiUrl/api/notes"),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                  "user_id": widget.username,
                  "title": titleController.text,
                  "content": contentController.text
                }),
              );
              Navigator.pop(context);
              _fetchNotes();
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sổ tay học tập"), backgroundColor: Colors.teal),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _notes.length,
            itemBuilder: (context, index) {
              final note = _notes[index];
              return Card(
                child: ListTile(
                  title: Text(note['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(note['content']),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await http.delete(Uri.parse("$apiUrl/api/notes/${note['id']}"));
                      _fetchNotes();
                    },
                  ),
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNoteDialog,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}