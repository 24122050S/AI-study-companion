import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';

class FlashcardScreen extends StatefulWidget {
  final String username;
  final String notebookId;
  final List<dynamic>? preloadedCards; 
  final int? deckId; 
  final bool isReviewMode; 
  final String? focusTopic; // 🚀 BỔ SUNG BIẾN NHẬN CHỦ ĐỀ

  const FlashcardScreen({
    super.key, 
    required this.username, 
    required this.notebookId, 
    this.preloadedCards, 
    this.deckId,
    this.isReviewMode = false,
    this.focusTopic, // 🚀 KHAI BÁO VÀO CONSTRUCTOR
  });

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _ScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<dynamic> _allCards = [];  
  List<dynamic> _dueCards = [];  
  
  bool _isLoading = false;
  int _currentIndex = 0;
  bool _isFlipped = false; 
  int? _currentDeckId;

  @override
  void initState() {
    super.initState();
    _currentDeckId = widget.deckId;
    if (widget.preloadedCards != null && widget.preloadedCards!.isNotEmpty) {
      _allCards = List.from(widget.preloadedCards!);
      _filterDueCards();
    } else {
      _fetchFlashcards();
    }
  }

  void _filterDueCards() {
    DateTime now = DateTime.now();
    _dueCards = _allCards.where((card) {
      if (card['due_date'] == null) return true;
      DateTime dueDate = DateTime.parse(card['due_date']);
      return dueDate.isBefore(now) || dueDate.isAtSameMomentAs(now);
    }).toList();
  }

  Future<void> _fetchFlashcards() async {
    setState(() { _isLoading = true; _allCards = []; _dueCards = []; _currentIndex = 0; _isFlipped = false; });
    try {
      if (widget.isReviewMode) {
        final response = await http.get(
          Uri.parse("${ApiConstants.baseUrl}/api/flashcards/due/${widget.notebookId}/${widget.username}"),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          setState(() {
            _dueCards = data["data"] ?? [];
          });
        }
      } 
      else {
        final response = await http.post(
          Uri.parse("${ApiConstants.baseUrl}/api/flashcards"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "user_id": widget.username, 
            "num_cards": 5, 
            "notebook_id": widget.notebookId,
            "focus_topic": widget.focusTopic // 🚀 GỬI CHỦ ĐỀ SANG CHO AI
          }),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          setState(() {
            _allCards = data["data"] ?? [];
            _currentDeckId = data["deck_id"]; 
            _filterDueCards();
          });
        }
      }
    } catch (e) { print("Lỗi tải Flashcard: $e"); }
    setState(() => _isLoading = false);
  }

  void _processReview(int quality) {
    var card = _dueCards[_currentIndex];
    
    double ease = (card['ease'] ?? 2.5).toDouble();
    int reps = card['reps'] ?? 0;
    int interval = card['interval'] ?? 0;
    int lapses = card['lapses'] ?? 0;

    if (quality >= 3) {
      if (reps == 0) {
        interval = 1; 
      } else if (reps == 1) {
        interval = 6; 
      } else {
        interval = (interval * ease).round(); 
      }
      reps++;
      ease = ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    } else {
      reps = 0;      
      interval = 1;  
      lapses++;      
      ease = ease - 0.2; 
    }

    if (ease < 1.3) ease = 1.3;

    card['ease'] = ease;
    card['reps'] = reps;
    card['interval'] = interval;
    card['lapses'] = lapses;
    card['last_reviewed'] = DateTime.now().toIso8601String();
    card['due_date'] = DateTime.now().add(Duration(days: interval)).toIso8601String();

    if (widget.isReviewMode) {
      _syncSingleCardToBackend(card);
    }

    setState(() {
      if (quality < 3) {
        _dueCards.add(card); 
      }
      _currentIndex++;
      _isFlipped = false;

      if (!widget.isReviewMode && _currentIndex >= _dueCards.length) {
        _syncProgressToBackend();
      }
    });
  }

  Future<void> _syncSingleCardToBackend(Map<String, dynamic> card) async {
    try {
      await http.put(
        Uri.parse("${ApiConstants.baseUrl}/api/flashcards/update_card"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.username,
          "deck_id": card['deck_id'],
          "card_index": card['card_index'],
          "card_data": {
            "ease": card['ease'],
            "reps": card['reps'],
            "interval": card['interval'],
            "lapses": card['lapses'],
            "due_date": card['due_date'],
            "last_reviewed": card['last_reviewed']
          }
        }),
      );
    } catch (e) { print("Lỗi đồng bộ thẻ đơn: $e"); }
  }

  Future<void> _syncProgressToBackend() async {
    if (_currentDeckId == null) return;
    try {
      await http.put(
        Uri.parse("${ApiConstants.baseUrl}/api/flashcards/deck/$_currentDeckId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.username, "cards": _allCards}),
      );
    } catch (e) { print("Lỗi đồng bộ SRS: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        title: Text(widget.isReviewMode ? "Ôn tập đến hạn (SRS)" : "Thẻ Flashcard", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigoAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigoAccent))
          : _dueCards.isEmpty 
              ? _buildFinishedScreen(isDoneForToday: true) 
              : _currentIndex >= _dueCards.length
                  ? _buildFinishedScreen(isDoneForToday: false) 
                  : _buildCardContent(),
    );
  }

  Widget _buildFinishedScreen({required bool isDoneForToday}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isDoneForToday ? Icons.check_circle : Icons.emoji_events, size: 100, color: isDoneForToday ? Colors.green : Colors.amber),
          const SizedBox(height: 20),
          Text(isDoneForToday ? "Hoàn thành nhiệm vụ!" : "Tuyệt vời!", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            isDoneForToday ? "Tuyệt đỉnh! Không còn thẻ nào đến hạn cần ôn tập." : "Bạn đã thuộc hết các thẻ đến hạn trong phiên này.", 
            style: const TextStyle(fontSize: 16, color: Colors.grey)
          ),
          const SizedBox(height: 30),
          if (!widget.isReviewMode)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
              onPressed: _fetchFlashcards,
              icon: const Icon(Icons.add_box, color: Colors.white),
              label: const Text("Tạo thêm thẻ mới", style: TextStyle(color: Colors.white, fontSize: 15)),
            )
        ],
      ),
    );
  }

  Widget _buildCardContent() {
    final currentCard = _dueCards[_currentIndex];
    double progress = (_currentIndex) / _dueCards.length;
    String stats = "Lần lặp: ${currentCard['reps'] ?? 0} | Quên: ${currentCard['lapses'] ?? 0}";

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          LinearProgressIndicator(value: progress, backgroundColor: Colors.grey[300], color: Colors.indigoAccent, minHeight: 8),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Đến hạn: ${_currentIndex + 1} / ${_dueCards.length}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo)),
              Text(stats, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 20),
          
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isFlipped = !_isFlipped),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isFlipped ? Colors.indigo.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15, spreadRadius: 1)],
                  border: Border.all(color: _isFlipped ? Colors.indigoAccent : Colors.transparent, width: 2)
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: ScrollConfiguration(
                      behavior: _ScrollBehavior(),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(currentCard['term'], textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _isFlipped ? Colors.indigo : Colors.black87)),
                            if (_isFlipped) ...[
                              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(color: Colors.indigoAccent)),
                              Text(currentCard['definition'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.6)),
                            ] else ...[
                              const SizedBox(height: 50),
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
            ),
          ),
          const SizedBox(height: 30),
          
          if (_isFlipped)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildReviewButton(Icons.close, "Quên", Colors.redAccent, () => _processReview(0)),
                _buildReviewButton(Icons.thumb_up, "Nhớ", Colors.green, () => _processReview(3)),
                _buildReviewButton(Icons.flash_on, "Dễ", Colors.blueAccent, () => _processReview(5)),
              ],
            )
          else
            const SizedBox(height: 60), 
        ],
      ),
    );
  }

  Widget _buildReviewButton(IconData icon, String label, Color color, VoidCallback onPressed) {
    return Column(
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color, shape: const CircleBorder(), padding: const EdgeInsets.all(18)),
          onPressed: onPressed,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}