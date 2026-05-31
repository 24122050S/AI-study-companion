import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';

class RoadmapScreen extends StatefulWidget {
  final String username;
  final String notebookId;

  const RoadmapScreen({super.key, required this.username, required this.notebookId});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  List<dynamic> _roadmapStages = [];
  int _currentStage = 1; // 🚀 BIẾN LƯU TRỮ TIẾN ĐỘ THUẬT TOÁN
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRoadmap();
  }

  Future<void> _fetchRoadmap() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/roadmap"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username,
          "notebook_id": widget.notebookId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _roadmapStages = data['data'] ?? [];
          _currentStage = data['current_stage'] ?? 1; // 🚀 ĐÓN DỮ LIỆU TỪ BACKEND
        });
      }
    } catch (e) {
      print("Lỗi tải lộ trình: $e");
    }
    setState(() => _isLoading = false);
  }

  void _showStageDetails(Map<String, dynamic> stage) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView( 
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_circle, color: Colors.green, size: 30),
                    const SizedBox(width: 10),
                    Expanded(child: Text("Giai đoạn ${stage['day']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green))),
                  ],
                ),
                const SizedBox(height: 10),
                Text(stage['title'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Icon(Icons.timer, size: 16, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text("Dự kiến: ${stage['estimated_time']}", style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider()),
                const Text("Nhiệm vụ của bạn:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                ...List.generate(
                  (stage['tasks'] as List).length,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("👉 ", style: TextStyle(fontSize: 16)),
                        Expanded(child: Text(stage['tasks'][index].toString(), style: const TextStyle(fontSize: 15, height: 1.4))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); 
                    Navigator.pop(context, stage); 
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  child: const Text("VÀO HỌC NGAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        title: const Text("Lộ trình học tập", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.indigo,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : _roadmapStages.isEmpty
              ? const Center(child: Text("Không có dữ liệu lộ trình."))
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _roadmapStages.length,
                  itemBuilder: (context, index) {
                    final stage = _roadmapStages[index];
                    
                    // 🚀 THUẬT TOÁN KIỂM TRA MỞ KHÓA: Nếu STT bài <= Tiến độ hiện tại
                    bool isUnlocked = (index + 1) <= _currentStage;

                    return GestureDetector(
                      onTap: () {
                        if (isUnlocked) {
                          _showStageDetails(stage);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("🔒 Giai đoạn bị khóa! Bạn phải vượt qua bài Quiz của Giai đoạn ${(index + 1) - 1} trước."),
                              backgroundColor: Colors.orange,
                            )
                          );
                        }
                      },
                      child: Stack(
                        children: [
                          if (index != _roadmapStages.length - 1)
                            Positioned(
                              left: 35,
                              top: 50,
                              bottom: -20,
                              child: Container(width: 3, color: isUnlocked ? Colors.indigo.shade200 : Colors.grey.shade300),
                            ),
                          
                          Card(
                            elevation: isUnlocked ? 4 : 0,
                            margin: const EdgeInsets.only(bottom: 20, left: 60),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: BorderSide(color: isUnlocked ? Colors.indigoAccent.withOpacity(0.5) : Colors.transparent, width: 2)
                            ),
                            color: isUnlocked ? Colors.white : Colors.grey.shade100,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Giai đoạn ${stage['day']}", 
                                        style: TextStyle(fontWeight: FontWeight.bold, color: isUnlocked ? Colors.indigo : Colors.grey)
                                      ),
                                      if (isUnlocked) 
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(8)),
                                          child: const Text("ĐANG MỞ", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                        )
                                      else
                                        const Icon(Icons.lock, color: Colors.grey, size: 16) // 🚀 THÊM Ổ KHÓA NHỎ
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    stage['title'], 
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isUnlocked ? Colors.black87 : Colors.grey),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.access_time, size: 14, color: isUnlocked ? Colors.orange : Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(stage['estimated_time'], style: TextStyle(fontSize: 12, color: isUnlocked ? Colors.orange.shade700 : Colors.grey)),
                                    ],
                                  ),
                                  
                                  // 🚀 HIỆN DÒNG CHỮ ĐỎ NHẮC NHỞ NẾU BỊ KHÓA
                                  if (!isUnlocked) ...[
                                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                                    Row(
                                      children: [
                                        const Icon(Icons.info_outline, size: 14, color: Colors.redAccent),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            "Yêu cầu: Đạt 80% bài Quiz của Giai đoạn ${index} để mở khóa", 
                                            style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w500)
                                          ),
                                        ),
                                      ],
                                    )
                                  ]

                                ],
                              ),
                            ),
                          ),
                          
                          Positioned(
                            left: 10,
                            top: 15,
                            child: CircleAvatar(
                              radius: 25,
                              backgroundColor: isUnlocked ? Colors.indigo : Colors.grey.shade300,
                              child: Icon(
                                isUnlocked ? Icons.play_arrow_rounded : Icons.lock_rounded, 
                                color: Colors.white, 
                                size: 28
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}