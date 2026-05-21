import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; // Thư viện để định dạng ngày tháng

class HistoryScreen extends StatefulWidget {
  final String username;
  const HistoryScreen({super.key, required this.username});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final String apiUrl = "http://10.0.195.105:8000";
  List<dynamic> _history = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse("$apiUrl/api/history/${widget.username}"));
      if (response.statusCode == 200) {
        setState(() {
          _history = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      print("Lỗi tải lịch sử: $e");
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Lịch sử học tập", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.indigo,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    double percent = item['percentage'] ?? 0.0;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: percent >= 80 ? Colors.green : (percent < 50 ? Colors.red : Colors.orange),
                          child: Text("${percent.toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        title: Text(item['topic'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Ngày làm: ${item['date'].split(' ')[0]}"),
                        trailing: Text("${item['score']} / ${item['total']}", 
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 10),
          const Text("Bạn chưa có bài làm nào. Hãy thử sức ngay!"),
        ],
      ),
    );
  }
}