import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'api_constants.dart';

const Color _bg         = Color(0xFFE8F5EE); 
const Color _bgDeep     = Color(0xFFD0EBE0); 
const Color _green1     = Color(0xFF4CAF7D); 
const Color _green2     = Color(0xFF2E7D5A); 
const Color _teal       = Color(0xFF3DA89A); 
const Color _orange     = Color(0xFFE8734A); 
const Color _cream      = Color(0xFFF5F0DC); 
const Color _darkText   = Color(0xFF1A3328); 
const Color _midText    = Color(0xFF4A7560); 
const Color _lightText  = Color(0xFF8AB8A0); 
const Color _cardWhite  = Color(0xFFFFFFFF); 

final _decorImages = [
  _DecorImg('assets/images/fc_books.png',   left: 0.02, top: 0.04,  size: 150, angle: -12),
  _DecorImg('assets/images/fc_plant.png',   left: -0.02, top: 0.65, size: 160, angle: 8),
  _DecorImg('assets/images/fc_pen.png',     left: 0.75, top: 0.02,  size: 140, angle: 20),
  _DecorImg('assets/images/fc_laptop.png',  left: 0.72, top: 0.42,  size: 155, angle: -8),
  _DecorImg('assets/images/fc_bag.png',     left: 0.70, top: 0.75,  size: 145, angle: 10),
];

class _DecorImg {
  final String path;
  final double left, top, size, angle;
  const _DecorImg(this.path, {required this.left, required this.top, required this.size, required this.angle});
}

class FlashcardScreen extends StatefulWidget {
  final String username;
  final String notebookId;
  final List<dynamic>? preloadedCards; 
  final int? deckId; 
  final bool isReviewMode; 
  final String? focusTopic;

  const FlashcardScreen({
    super.key, 
    required this.username, 
    required this.notebookId, 
    this.preloadedCards, 
    this.deckId,
    this.isReviewMode = false,
    this.focusTopic,
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

class _FlashcardScreenState extends State<FlashcardScreen> with TickerProviderStateMixin {
  List<dynamic> _allCards = [];  
  List<dynamic> _dueCards = [];  
  
  bool _isLoading = false;
  int _currentIndex = 0;
  bool _isFlipped = false; 
  int? _currentDeckId;

  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;
  late AnimationController _floatCtrl;
  late AnimationController _cardEnterCtrl;
  late Animation<double> _cardEnterAnim;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _flipAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutCubic));

    _floatCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);

    _cardEnterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _cardEnterAnim = CurvedAnimation(parent: _cardEnterCtrl, curve: Curves.easeOutBack);
    _cardEnterCtrl.forward();

    _currentDeckId = widget.deckId;
    if (widget.preloadedCards != null && widget.preloadedCards!.isNotEmpty) {
      _allCards = List.from(widget.preloadedCards!);
      _filterDueCards();
    } else {
      _fetchFlashcards();
    }
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _floatCtrl.dispose();
    _cardEnterCtrl.dispose();
    super.dispose();
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
    _flipCtrl.reset();
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
      } else {
        final response = await http.post(
          Uri.parse("${ApiConstants.baseUrl}/api/flashcards"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "user_id": widget.username, 
            "num_cards": 5, 
            "notebook_id": widget.notebookId,
            "focus_topic": widget.focusTopic
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
    } catch (e) { debugPrint("Lỗi tải Flashcard: $e"); }
    setState(() => _isLoading = false);
    _cardEnterCtrl.forward(from: 0);
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

    _cardEnterCtrl.forward(from: 0);
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
    _flipCtrl.reset();
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
    } catch (e) { debugPrint("Lỗi đồng bộ thẻ đơn: $e"); }
  }

  Future<void> _syncProgressToBackend() async {
    if (_currentDeckId == null) return;
    try {
      await http.put(
        Uri.parse("${ApiConstants.baseUrl}/api/flashcards/deck/$_currentDeckId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.username, "cards": _allCards}),
      );
    } catch (e) { debugPrint("Lỗi đồng bộ SRS: $e"); }
  }

  void _flipCard() {
    _isFlipped ? _flipCtrl.reverse() : _flipCtrl.forward();
    setState(() => _isFlipped = !_isFlipped);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          _buildBackground(),
          ..._buildDecorImages(size),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _isLoading
                      ? _buildLoadingState()
                      : _dueCards.isEmpty 
                          ? _buildFinishedScreen(isDoneForToday: true) 
                          : _currentIndex >= _dueCards.length
                              ? _buildFinishedScreen(isDoneForToday: false) 
                              : _buildCardContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE2F5EC), Color(0xFFCCEBDF), Color(0xFFD8EFF6)],
        ),
      ),
      child: Stack(children: [
        Positioned(top: -80, left: -60, child: _blob(280, _green1.withOpacity(0.12))),
        Positioned(bottom: -60, right: -40, child: _blob(260, _teal.withOpacity(0.12))),
        Positioned(top: 200, right: 50, child: _blob(150, _orange.withOpacity(0.08))),
        Positioned.fill(child: CustomPaint(painter: _DotGridPainter(_green2.withOpacity(0.07)))),
      ]),
    );
  }

  Widget _blob(double size, Color color) {
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
  }

  List<Widget> _buildDecorImages(Size size) {
    return _decorImages.map((img) {
      final phaseOffset = _decorImages.indexOf(img) * 0.2;
      return AnimatedBuilder(
        animation: _floatCtrl,
        builder: (_, child) {
          final t = (_floatCtrl.value + phaseOffset) % 1.0;
          final dy = math.sin(t * math.pi * 2) * 8;
          final dx = math.cos(t * math.pi) * 4;
          return Positioned(
            left: size.width * img.left,
            top: size.height * img.top,
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Transform.rotate(
                angle: img.angle * math.pi / 180,
                child: Opacity(
                  opacity: 0.82,
                  child: Image.asset(img.path, width: img.size, height: img.size, fit: BoxFit.contain),
                ),
              ),
            ),
          );
        },
      );
    }).toList();
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 24, 12),
      decoration: BoxDecoration(
        color: _cardWhite.withOpacity(0.7),
        border: Border(bottom: BorderSide(color: _green1.withOpacity(0.15), width: 1.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _green1.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green1.withOpacity(0.3), width: 1.5),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: _darkText, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.isReviewMode ? "Ôn tập đến hạn (SRS)" : "Thẻ Flashcard",
                  style: const TextStyle(color: _darkText, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              Text(widget.notebookId,
                  style: const TextStyle(color: _lightText, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: _green2, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.auto_stories, color: _cream, size: 17),
            ),
            const SizedBox(width: 8),
            RichText(text: const TextSpan(children: [
              TextSpan(text: "Learn", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _darkText, letterSpacing: 0.3)),
              TextSpan(text: "ify", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _green1, letterSpacing: 0.3)),
            ])),
          ]),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 52, height: 52,
          child: CircularProgressIndicator(color: _green1, backgroundColor: _green1.withOpacity(0.15), strokeWidth: 3)),
        const SizedBox(height: 20),
        const Text("Đang tải flashcard...",
            style: TextStyle(color: _midText, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.3)),
      ]),
    );
  }

  Widget _buildFinishedScreen({required bool isDoneForToday}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isDoneForToday ? [_green1, _teal] : [const Color(0xFFF9A826), const Color(0xFFFF4B2B)], 
                begin: Alignment.topLeft, end: Alignment.bottomRight
              ),
              boxShadow: [BoxShadow(
                color: isDoneForToday ? _green1.withOpacity(0.35) : Colors.orange.withOpacity(0.35), 
                blurRadius: 30, spreadRadius: 4
              )],
            ),
            child: Icon(isDoneForToday ? Icons.check_circle_rounded : Icons.emoji_events_rounded, size: 54, color: Colors.white),
          ),
          const SizedBox(height: 28),
          Text(isDoneForToday ? "Hoàn thành nhiệm vụ!" : "Xuất sắc! 🎉",
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _darkText, letterSpacing: -0.5)),
          const SizedBox(height: 10),
          Text(isDoneForToday ? "Tuyệt đỉnh! Không còn thẻ nào đến hạn cần ôn tập." : "Bạn đã thuộc hết các thẻ đến hạn trong phiên này.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: _midText, height: 1.6)),
          const SizedBox(height: 28),
          if (!widget.isReviewMode)
            GestureDetector(
              onTap: _fetchFlashcards,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _green2,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: _green2.withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_box_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text("Tạo thêm thẻ mới", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildCardContent() {
    final currentCard = _dueCards[_currentIndex];
    final double progress = _currentIndex / _dueCards.length;
    final String stats = "Lần lặp: ${currentCard['reps'] ?? 0} | Quên: ${currentCard['lapses'] ?? 0}";

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProgressBar(progress, stats),
              const SizedBox(height: 24),

              ScaleTransition(
                scale: _cardEnterAnim,
                child: GestureDetector(
                  onTap: _flipCard,
                  child: SizedBox(
                    height: 300, 
                    child: AnimatedBuilder(
                      animation: _flipAnim,
                      builder: (_, __) {
                        final angle = _flipAnim.value * math.pi;
                        final isBack = angle > math.pi / 2;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          child: isBack
                              ? Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()..rotateY(math.pi),
                                  child: _buildCardFace(isBack: true, term: currentCard['term'] ?? '', definition: currentCard['definition'] ?? ''),
                                )
                              : _buildCardFace(isBack: false, term: currentCard['term'] ?? '', definition: currentCard['definition'] ?? ''),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: _isFlipped
                    ? Row(key: const ValueKey('btns'), mainAxisAlignment: MainAxisAlignment.center, children: [
                        _reviewBtn("Quên", Icons.close_rounded, const Color(0xFFE8604A), () => _processReview(0)),
                        const SizedBox(width: 12),
                        _reviewBtn("Nhớ", Icons.thumb_up_rounded, _green1, () => _processReview(3)),
                        const SizedBox(width: 12),
                        _reviewBtn("Dễ", Icons.flash_on_rounded, const Color(0xFF4A90E2), () => _processReview(5)),
                      ])
                    : _buildHintBar(key: const ValueKey('hint')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(double progress, String stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Tiến trình  •  $stats",
                style: const TextStyle(fontSize: 12, color: _midText, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            Text(
              "${_currentIndex + 1} / ${_dueCards.length}",
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _green2),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(children: [
                Container(height: 8, color: _green1.withOpacity(0.12)),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  height: 8,
                  width: constraints.maxWidth * progress,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [_green1, _teal], begin: Alignment.centerLeft, end: Alignment.centerRight),
                  ),
                ),
              ]),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHintBar({Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _cardWhite.withOpacity(0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green1.withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: _green1.withOpacity(0.08), blurRadius: 10)],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.touch_app_rounded, color: _green1, size: 18),
        const SizedBox(width: 8),
        const Text("Chạm để lật thẻ",
            style: TextStyle(color: _green2, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      ]),
    );
  }

  Widget _reviewBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 5))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardFace({required bool isBack, required String term, required String definition}) {
    final Color accent = isBack ? _teal : _green1;
    final Color bgColor = isBack ? const Color(0xFFF0FAF8) : const Color(0xFFF5FBF0);
    final Color accentDark = isBack ? _green2 : const Color(0xFF2E6B45);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withOpacity(0.4), width: 2),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 8)),
          const BoxShadow(color: Colors.white, blurRadius: 0, offset: Offset(0, 0)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: CustomPaint(painter: _CardPatternPainter(accent)),
          )),

          Positioned(top: 16, left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withOpacity(0.35), width: 1.5),
              ),
              child: Text("${_currentIndex + 1}/${_dueCards.length}",
                  style: TextStyle(color: accentDark, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),

          Positioned(top: 28, bottom: 28, left: 0,
            child: Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
              ),
            ),
          ),

          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 40, 36, 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
                    ),
                    child: Text(
                      isBack ? "ĐỊNH NGHĨA" : "THUẬT NGỮ",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accentDark, letterSpacing: 2),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    term,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: _darkText,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),

                  if (isBack) ...[
                    const SizedBox(height: 14),
                    Container(height: 1.5, color: accent.withOpacity(0.3)),
                    const SizedBox(height: 14),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Text(
                          definition,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, color: _midText, height: 1.55, letterSpacing: 0.1),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    Icon(Icons.touch_app_rounded, color: accent, size: 28),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  const _DotGridPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeCap = StrokeCap.round;
    const spacing = 36.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _CardPatternPainter extends CustomPainter {
  final Color accent;
  const _CardPatternPainter(this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = accent.withOpacity(0.04)..strokeWidth = 1;
    const spacing = 40.0;
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override bool shouldRepaint(_) => false;
}