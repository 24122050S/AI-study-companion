import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class FlashcardScreen extends StatefulWidget {
  final String username;
  const FlashcardScreen({super.key, required this.username});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  final String apiUrl = "http://10.0.195.105:8000";
  List<dynamic> _flashcards = [];
  bool _isLoading = false;
  
  int _currentIndex = 0;
  bool _isFlipped = false; // Trạng thái lật thẻ (Mặt trước / Mặt sau)

  @override
  void initState() {
    super.initState();
    _fetchFlashcards();
  }

  Future<void> _fetchFlashcards() async {
    setState(() {
      _isLoading = true;
      _flashcards = [];
      _currentIndex = 0;
      _isFlipped = false;
    });

    try {
      final response = await http.post(
        Uri.parse("$apiUrl/api/flashcards"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.username, "num_cards": 5}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _flashcards = data["data"] ?? [];
        });
      }
    } catch (e) {
      print("Lỗi tải Flashcard: $e");
    }
    setState(() => _isLoading = false);
  }

  void _nextCard(bool isLearned) {
    setState(() {
      if (!isLearned) {
        // Nếu chưa thuộc, tống thẻ này xuống cuối danh sách để tí học lại
        _flashcards.add(_flashcards[_currentIndex]);
      }
      
      _currentIndex++;
      _isFlipped = false; // Trả thẻ về mặt trước cho câu tiếp theo
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("Ôn tập Flashcard", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.purpleAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
          : _currentIndex >= _flashcards.length
              ? _buildFinishedScreen()
              : _buildCardContent(),
    );
  }

  Widget _buildFinishedScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events, size: 100, color: Colors.amber),
          const SizedBox(height: 20),
          const Text("Chúc mừng!", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text("Bạn đã thuộc hết tất cả các thẻ ghi nhớ.", style: TextStyle(fontSize: 16)),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
            onPressed: _fetchFlashcards,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text("Tạo bộ thẻ mới từ PDF", style: TextStyle(color: Colors.white, fontSize: 16)),
          )
        ],
      ),
    );
  }

  Widget _buildCardContent() {
    final currentCard = _flashcards[_currentIndex];
    // Tính phần trăm tiến độ
    double progress = (_currentIndex) / _flashcards.length;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          // Thanh tiến trình
          LinearProgressIndicator(value: progress, backgroundColor: Colors.grey[300], color: Colors.purpleAccent, minHeight: 8),
          const SizedBox(height: 20),
          Text("Thẻ số ${_currentIndex + 1} / ${_flashcards.length}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 20),
          
          // Thẻ lật
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _isFlipped = !_isFlipped);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isFlipped ? Colors.purple[50] : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)],
                  border: Border.all(color: _isFlipped ? Colors.purpleAccent : Colors.transparent, width: 2)
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          currentCard['term'],
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _isFlipped ? Colors.purple : Colors.black87),
                        ),
                        if (_isFlipped) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Divider(color: Colors.purpleAccent),
                          ),
                          Text(
                            currentCard['definition'],
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.5),
                          ),
                        ] else ...[
                          const SizedBox(height: 40),
                          const Icon(Icons.touch_app, color: Colors.grey, size: 40),
                          const SizedBox(height: 10),
                          const Text("Chạm để lật thẻ", style: TextStyle(color: Colors.grey)),
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 30),
          
          // 2 Nút bấm (Chỉ hiện khi đã lật thẻ)
          if (_isFlipped)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                  onPressed: () => _nextCard(false), // Chưa thuộc
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text("Học lại sau", style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                  onPressed: () => _nextCard(true), // Đã thuộc
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text("Đã thuộc", style: TextStyle(color: Colors.white)),
                ),
              ],
            )
          else
            const SizedBox(height: 50), // Chiếm chỗ trống để giao diện không bị giật cục
        ],
      ),
    );
  }
}