import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RoadmapScreen extends StatefulWidget {
  final String username;
  const RoadmapScreen({super.key, required this.username});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  final String apiUrl = "http://localhost:8000";
  List<dynamic> _roadmap = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchRoadmap();
  }

  Future<void> _fetchRoadmap() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("$apiUrl/api/roadmap"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.username}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _roadmap = data["data"] ?? [];
        });
      }
    } catch (e) {
      print("Lỗi tải lộ trình: $e");
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Lộ trình Học khoa học", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepOrangeAccent,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _fetchRoadmap)
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepOrangeAccent))
          : _roadmap.isEmpty
              ? const Center(child: Text("Không có dữ liệu lộ trình."))
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _roadmap.length,
                  itemBuilder: (context, index) {
                    final stage = _roadmap[index];
                    final List<dynamic> tasks = stage['tasks'] ?? [];
                    final bool isLast = index == _roadmap.length - 1;

                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // CỘT TIMELINE BÊN TRÁI
                          Column(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.deepOrangeAccent,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.deepOrange.withOpacity(0.4), blurRadius: 8)],
                                ),
                                child: Center(child: Text("${index + 1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
                              ),
                              if (!isLast) // Đường kẻ dọc nối liền
                                Expanded(
                                  child: Container(width: 3, color: Colors.deepOrangeAccent.withOpacity(0.3)),
                                )
                            ],
                          ),
                          const SizedBox(width: 20),
                          
                          // CỘT NỘI DUNG BÊN PHẢI
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 30),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                                  border: Border(left: BorderSide(color: Colors.deepOrangeAccent, width: 4))
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(stage['day'], style: const TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(height: 5),
                                    Text(stage['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                                    const SizedBox(height: 15),
                                    const Divider(),
                                    ...tasks.map((task) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(child: Text(task.toString(), style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4))),
                                        ],
                                      ),
                                    )),
                                  ],
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}