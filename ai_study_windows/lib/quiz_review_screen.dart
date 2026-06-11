import 'package:flutter/material.dart';

// ─── BẢNG MÀU (đồng bộ với quiz_screen.dart) ────────────────────────────────
const Color cBg         = Color(0xFFEAF6F2);
const Color cMint       = Color(0xFF6DBFAB);
const Color cMintDark   = Color(0xFF4A9E8C);
const Color cCoral      = Color(0xFFE8604A);
const Color cCoralLight = Color(0xFFF5957F);
const Color cDark       = Color(0xFF1D3330);
const Color cCard       = Color(0xFFFFFFFF);
const Color cCardTinted = Color(0xFFF0FAF7);
const Color cText       = Color(0xFF2C4A45);
const Color cTextLight  = Color(0xFF7A9E99);
const Color cYellow     = Color(0xFFFFCC5C);
const Color cPeach      = Color(0xFFF5C8B8);

class QuizReviewScreen extends StatelessWidget {
  final List<dynamic> questions;
  final Map<int, String> userAnswers;

  const QuizReviewScreen({
    super.key,
    required this.questions,
    required this.userAnswers,
  });

  // ─── TÍNH THỐNG KÊ ─────────────────────────────────────────────────────────
  int get _correctCount =>
      List.generate(questions.length, (i) => i)
          .where((i) => userAnswers[i] == questions[i]['answer'])
          .length;

  int get _skippedCount =>
      List.generate(questions.length, (i) => i)
          .where((i) => userAnswers[i] == null)
          .length;

  int get _wrongCount => questions.length - _correctCount - _skippedCount;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: cBg,
      body: Column(
        children: [
          _buildTopBar(context),
          Expanded(
            child: isDesktop
                ? _buildDesktopLayout(size)
                : _buildMobileLayout(),
          ),
        ],
      ),
      floatingActionButton: _buildHomeButton(context),
    );
  }

  // ─── TOP BAR ────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: cCard,
        boxShadow: [
          BoxShadow(color: cMint.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _TopBarBtn(
              icon: Icons.arrow_back_rounded,
              color: cBg,
              iconColor: cDark,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 14),
            // Badge: Xem lại bài làm
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cMint.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cMint.withOpacity(0.3), width: 1),
              ),
              child: const Row(children: [
                Icon(Icons.rule_rounded, color: cMint, size: 16),
                SizedBox(width: 6),
                Text(
                  "Xem lại bài làm",
                  style: TextStyle(color: cMint, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            // Badge: tổng câu
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cDark.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "${questions.length} câu",
                style: const TextStyle(color: cText, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const Spacer(),
            _TopBarBtn(
              icon: Icons.home_rounded,
              color: cBg,
              iconColor: cDark,
              onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ],
        ),
      ),
    );
  }

  // ─── DESKTOP: 2 CỘT ─────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(Size size) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 60, child: _buildReviewList()),
        SizedBox(width: size.width * 0.38, child: _buildSummaryPanel()),
      ],
    );
  }

  // ─── MOBILE ──────────────────────────────────────────────────────────────────
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildScoreBar(),
        Expanded(child: _buildReviewList()),
      ],
    );
  }

  // ─── SCORE BAR (mobile) ──────────────────────────────────────────────────────
  Widget _buildScoreBar() {
    final pct = questions.isEmpty ? 0.0 : _correctCount / questions.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: cMint.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatChip(icon: Icons.check_circle_rounded, label: "Đúng", value: "$_correctCount", color: cMint),
            _StatChip(icon: Icons.cancel_rounded, label: "Sai", value: "$_wrongCount", color: cCoral),
            _StatChip(icon: Icons.help_outline_rounded, label: "Bỏ trống", value: "$_skippedCount", color: cYellow),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: cMint.withOpacity(0.15),
            valueColor: const AlwaysStoppedAnimation<Color>(cMint),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Điểm chính xác", style: TextStyle(fontSize: 11.5, color: cTextLight, fontWeight: FontWeight.w600)),
            Text("${(pct * 100).toStringAsFixed(1)}%",
                style: const TextStyle(fontSize: 11.5, color: cMintDark, fontWeight: FontWeight.w800)),
          ],
        ),
      ]),
    );
  }

  // ─── DANH SÁCH CÂU HỎI ──────────────────────────────────────────────────────
  Widget _buildReviewList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _buildReviewCard(questions[index], index),
            ),
          ),
        );
      },
    );
  }

  // ─── CARD TỪNG CÂU ───────────────────────────────────────────────────────────
  Widget _buildReviewCard(dynamic q, int index) {
    final String correctAnswer = q['answer'].toString();
    final String? selected = userAnswers[index];
    final bool isCorrect = selected == correctAnswer;
    final bool isSkipped = selected == null;

    // Màu theme theo kết quả
    final Color themeColor = isCorrect ? cMint : (isSkipped ? cYellow : cCoral);
    final List<dynamic> options = (q['options'] as List?) ?? [];

    return Container(
      decoration: BoxDecoration(
        color: cCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: cMint.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header câu hỏi ──
          Container(
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Số thứ tự
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(10)),
                  child: Center(
                    child: Text(
                      "${index + 1}",
                      style: const TextStyle(color: cCard, fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    (q['question'] ?? "").toString(),
                    style: const TextStyle(color: cDark, fontSize: 16, fontWeight: FontWeight.w800, height: 1.45),
                  ),
                ),
                const SizedBox(width: 8),
                // Badge kết quả
                _ResultBadge(isCorrect: isCorrect, isSkipped: isSkipped),
              ],
            ),
          ),

          // ── Các đáp án ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (options.isNotEmpty)
                  ...options.map((opt) {
                    final String optText = opt.toString();
                    final bool isThisCorrect = optText == correctAnswer;
                    final bool isThisSelected = selected == optText;
                    final bool isThisWrong = isThisSelected && !isThisCorrect;

                    return _ReviewOptionTile(
                      text: optText,
                      state: isThisCorrect
                          ? _OptionState.correct
                          : isThisWrong
                              ? _OptionState.wrong
                              : _OptionState.normal,
                      isSelected: isThisSelected,
                    );
                  })
                else
                  // Hiển thị dạng text nếu không có options (trắc nghiệm tự luận)
                  _buildTextReview(selected, correctAnswer, isSkipped),

                // ── Nhãn kết quả cuối card ──
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: themeColor.withOpacity(0.1),
                    border: Border.all(color: themeColor, width: 1.5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isCorrect
                            ? Icons.check_circle_rounded
                            : (isSkipped ? Icons.help_outline_rounded : Icons.cancel_rounded),
                        color: isCorrect ? cMintDark : (isSkipped ? cYellow : cCoral),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isCorrect
                              ? "✅ Tuyệt vời! Bạn đã chọn đúng."
                              : isSkipped
                                  ? "⚠️ Bạn đã bỏ trống. Đáp án đúng: $correctAnswer"
                                  : "❌ Sai. Đáp án đúng là: $correctAnswer",
                          style: TextStyle(
                            color: isCorrect ? cMintDark : (isSkipped ? const Color(0xFF8A6200) : cCoral),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextReview(String? selected, String correct, bool isSkipped) {
    return Column(
      children: [
        _ReviewOptionTile(
          text: isSkipped ? "Bỏ trống" : selected!,
          state: isSkipped ? _OptionState.normal : (selected == correct ? _OptionState.correct : _OptionState.wrong),
          isSelected: true,
        ),
        if (!isSkipped && selected != correct)
          _ReviewOptionTile(text: correct, state: _OptionState.correct, isSelected: false),
      ],
    );
  }

  // ─── PANEL BÊN PHẢI (desktop) ────────────────────────────────────────────────
  Widget _buildSummaryPanel() {
    final pct = questions.isEmpty ? 0.0 : _correctCount / questions.length;

    return Container(
      color: cBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          // Vòng tròn điểm
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cCard,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: cMint.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Column(children: [
              const Text("Kết quả bài làm", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cDark)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cMint.withOpacity(0.12),
                  border: Border.all(color: cMint.withOpacity(0.3), width: 2),
                ),
                child: Text(
                  "${(pct * 100).toStringAsFixed(0)}%",
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: cMint),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Đúng $_correctCount / ${questions.length} câu",
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cText),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // Thống kê chi tiết
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cCard,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: cMint.withOpacity(0.1), blurRadius: 16)],
            ),
            child: Column(children: [
              _StatRow(icon: Icons.check_circle_rounded, label: "Trả lời đúng", value: "$_correctCount câu", color: cMint),
              const Divider(height: 20),
              _StatRow(icon: Icons.cancel_rounded, label: "Trả lời sai", value: "$_wrongCount câu", color: cCoral),
              const Divider(height: 20),
              _StatRow(icon: Icons.help_outline_rounded, label: "Bỏ trống", value: "$_skippedCount câu", color: cYellow),
            ]),
          ),

          const SizedBox(height: 16),

          // Thanh tiến trình
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cCard,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: cMint.withOpacity(0.1), blurRadius: 12)],
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Tiến độ", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cDark)),
                Text("$_correctCount/${questions.length} câu đúng",
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cMint)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: cMint.withOpacity(0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(cMint),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // Ghi chú / tips
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cCoralLight.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cCoral.withOpacity(0.2), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.lightbulb_rounded, color: cYellow, size: 16),
                  SizedBox(width: 6),
                  Text("Nhận xét", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: cCoral)),
                ]),
                const SizedBox(height: 10),
                Text(
                  pct >= 0.8
                      ? "🎉 Xuất sắc! Bạn nắm bài rất tốt."
                      : pct >= 0.5
                          ? "📘 Khá tốt! Ôn lại các câu sai để cải thiện thêm nhé."
                          : "💪 Hãy ôn tập kỹ hơn và thử lại, bạn sẽ làm được!",
                  style: const TextStyle(fontSize: 12.5, color: cText, height: 1.5),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ─── NÚT VỀ TRANG CHỦ (FAB) ─────────────────────────────────────────────────
  Widget _buildHomeButton(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: cMintDark,
      elevation: 6,
      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
      icon: const Icon(Icons.home_rounded, color: cCard),
      label: const Text("Về trang chủ", style: TextStyle(color: cCard, fontWeight: FontWeight.w700)),
    );
  }
}

// ─── COMPONENTS ──────────────────────────────────────────────────────────────

// Badge kết quả góc phải header card
class _ResultBadge extends StatelessWidget {
  final bool isCorrect, isSkipped;
  const _ResultBadge({required this.isCorrect, required this.isSkipped});

  @override
  Widget build(BuildContext context) {
    final Color color = isCorrect ? cMint : (isSkipped ? cYellow : cCoral);
    final IconData icon = isCorrect
        ? Icons.check_circle_rounded
        : (isSkipped ? Icons.help_outline_rounded : Icons.cancel_rounded);
    final String label = isCorrect ? "Đúng" : (isSkipped ? "Bỏ trống" : "Sai");

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }
}

// Tile đáp án review (readonly, thể hiện đúng/sai/bình thường)
enum _OptionState { normal, correct, wrong }

class _ReviewOptionTile extends StatelessWidget {
  final String text;
  final _OptionState state;
  final bool isSelected;

  const _ReviewOptionTile({required this.text, required this.state, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    Color fill = cCardTinted;
    Color border = cMint.withOpacity(0.25);
    Color textCol = cText;
    Color circleColor = cTextLight;

    if (state == _OptionState.correct) {
      fill = cMint.withOpacity(0.15);
      border = cMint;
      textCol = cMintDark;
      circleColor = cMint;
    } else if (state == _OptionState.wrong) {
      fill = cCoral.withOpacity(0.1);
      border = cCoral;
      textCol = cCoral;
      circleColor = cCoral;
    } else if (isSelected) {
      fill = cMint.withOpacity(0.08);
      border = cMint.withOpacity(0.5);
      textCol = cDark;
      circleColor = cTextLight;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.5),
          boxShadow: state != _OptionState.normal
              ? [BoxShadow(color: border.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]
              : [],
        ),
        child: Row(children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: circleColor, width: 2),
              color: state != _OptionState.normal || isSelected
                  ? circleColor.withOpacity(0.15)
                  : Colors.transparent,
            ),
            child: Center(
              child: state == _OptionState.correct
                  ? Icon(Icons.check, size: 14, color: circleColor)
                  : state == _OptionState.wrong
                      ? Icon(Icons.close, size: 14, color: circleColor)
                      : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textCol, fontWeight: FontWeight.w600, fontSize: 14.5, height: 1.4),
            ),
          ),
        ]),
      ),
    );
  }
}

// Chip thống kê nhỏ (dùng trên mobile)
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12)),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
      Text(label, style: const TextStyle(color: cTextLight, fontSize: 11, fontWeight: FontWeight.w500)),
    ]);
  }
}

// Hàng thống kê chi tiết (dùng trên desktop)
class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _StatRow({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: cText, fontWeight: FontWeight.w600))),
      Text(value, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w800)),
    ]);
  }
}

// Nút vuông trên TopBar
class _TopBarBtn extends StatelessWidget {
  final IconData icon;
  final Color color, iconColor;
  final VoidCallback onTap;
  const _TopBarBtn({required this.icon, required this.color, required this.iconColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }
}