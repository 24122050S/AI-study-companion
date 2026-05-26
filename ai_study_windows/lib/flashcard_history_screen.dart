import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';
import 'flashcard_screen.dart';

class FlashcardHistoryScreen extends StatefulWidget {
  final String username;
  final String notebookId;

  const FlashcardHistoryScreen({super.key, required this.username, required this.notebookId});

  @override
  State<FlashcardHistoryScreen> createState() => _FlashcardHistoryScreenState();
}

class _FlashcardHistoryScreenState extends State<FlashcardHistoryScreen> {
  List<dynamic> _historyDecks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final response = await http.get(
        Uri.parse("${ApiConstants.baseUrl}/api/flashcards/history/${widget.notebookId}?user_id=${widget.username}")
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes))['data'];
        setState(() {
          _historyDecks = data ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _reviewDeck(int deckId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.purple)),
    );

    try {
      final response = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/flashcards/deck/$deckId"));
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (response.statusCode == 200) {
        final cards = jsonDecode(utf8.decode(response.bodyBytes))['data'];
        
        // Mở FlashcardScreen và truyền BỘ THẺ CŨ vào
        Navigator.push(context, MaterialPageRoute(builder: (context) => FlashcardScreen(
          username: widget.username,
          notebookId: widget.notebookId,
          preloadedCards: cards, 
        )));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi tải bộ thẻ!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Lịch sử Bộ thẻ Flashcard", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.purpleAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
          : _historyDecks.isEmpty
              ? const Center(child: Text("Bạn chưa tạo bộ thẻ nào trong dự án này."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _historyDecks.length,
                  itemBuilder: (context, index) {
                    final deck = _historyDecks[index];
                    final date = DateTime.parse(deck['created_at']).toLocal();
                    final dateString = "${date.day}/${date.month}/${date.year} - ${date.hour}:${date.minute.toString().padLeft(2, '0')}";

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFF3E5F5),
                          child: Icon(Icons.style, color: Colors.purpleAccent),
                        ),
                        title: Text(deck['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(dateString),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () => _reviewDeck(deck['id']),
                      ),
                    );
                  },
                ),
    );
  }
}