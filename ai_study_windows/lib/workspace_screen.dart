import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'home_screen.dart';
import 'api_constants.dart';

const Color cInk      = Color(0xFF1A1209);
const Color cPaper    = Color(0xFFF5EFE0);
const Color cGold     = Color(0xFFD4A847);
const Color cRust     = Color(0xFFB94A2C);
const Color cForest   = Color(0xFF3D6B4F);
const Color cSky      = Color(0xFF3B7A9E);
const Color cLavender = Color(0xFF7B6FAE);
const Color cCream    = Color(0xFFFAF6ED);
const Color cSmoke    = Color(0xFFE8E0D0);

class WorkspaceScreen extends StatefulWidget {
  final String username;
  const WorkspaceScreen({super.key, required this.username});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with TickerProviderStateMixin {
  List<dynamic> _notebooks = [];
  bool _isLoading = false;

  late AnimationController _entranceAnim;
  late AnimationController _floatAnim;

  @override
  void initState() {
    super.initState();
    _entranceAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..forward();
    _floatAnim = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat(reverse: true);
    _fetchNotebooks();
  }

  @override
  void dispose() {
    _entranceAnim.dispose();
    _floatAnim.dispose();
    super.dispose();
  }

  Future<void> _fetchNotebooks() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse("${ApiConstants.baseUrl}/api/notebooks/${widget.username}"));
      if (res.statusCode == 200) {
        setState(() { _notebooks = jsonDecode(utf8.decode(res.bodyBytes)); });
      }
    } catch (e) {
      debugPrint(e.toString());
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createNotebook(String title) async {
    if (title.trim().isEmpty) return;
    try {
      await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/notebooks"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.username, "title": title.trim()}),
      );
      _fetchNotebooks();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _executeDeleteNotebook(int notebookId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: cRust)),
    );

    try {
      final response = await http.delete(
        Uri.parse("${ApiConstants.baseUrl}/api/notebooks/$notebookId"),
      );

      if (!mounted) return;
      Navigator.pop(context);

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(responseData['message'] ?? "Đã xóa dự án thành công!"), backgroundColor: cForest),
        );
        _fetchNotebooks();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Không thể xóa dự án từ máy chủ."), backgroundColor: cRust),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi kết nối máy chủ."), backgroundColor: cRust),
      );
    }
  }

  Future<void> _executeRenameNotebook(int notebookId, String newTitle) async {
    if (newTitle.trim().isEmpty) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: cSky)),
    );

    try {
      final response = await http.put(
        Uri.parse("${ApiConstants.baseUrl}/api/notebooks/$notebookId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"title": newTitle.trim()}),
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        _fetchNotebooks();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đã đổi tên thành công!"), backgroundColor: cForest)
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi kết nối máy chủ!"), backgroundColor: cRust)
      );
    }
  }

  void _showDeleteDialog(int notebookId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cCream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: cRust, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text("Xóa dự án?", style: TextStyle(color: cInk, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(
          "Hành động này không thể hoàn tác! Toàn bộ file tài liệu, lịch sử chat và các bộ đề trắc nghiệm thuộc dự án '$title' sẽ bị xóa sạch.",
          style: TextStyle(fontSize: 15, height: 1.4, color: cInk.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Hủy bỏ", style: TextStyle(color: cInk.withOpacity(0.5))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cRust,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context); 
              _executeDeleteNotebook(notebookId); 
            },
            child: const Text("Xóa vĩnh viễn", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(int notebookId, String currentTitle) {
    TextEditingController _control = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cCream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Đổi tên Dự án", style: TextStyle(color: cInk, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _control, 
          autofocus: true,
          style: TextStyle(color: cInk),
          decoration: InputDecoration(
            hintText: "Nhập tên mới...",
            hintStyle: TextStyle(color: cInk.withOpacity(0.4)),
            filled: true,
            fillColor: cSmoke,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: Text("Hủy", style: TextStyle(color: cInk.withOpacity(0.5)))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cSky,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _executeRenameNotebook(notebookId, _control.text);
            }, 
            child: const Text("Lưu thay đổi", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }

  void _showCreateDialog() {
    final ctrl = TextEditingController();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "dismiss",
      barrierColor: cInk.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (_, anim, __, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (_, __, ___) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: cCream,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: cInk.withOpacity(0.25), blurRadius: 50, offset: const Offset(0, 16))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: cRust, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Notebook Mới", style: TextStyle(color: cInk, fontSize: 20, fontWeight: FontWeight.w900)),
                    Text("Đặt tên cho hành trình", style: TextStyle(color: cInk.withOpacity(0.38), fontSize: 12)),
                  ]),
                ]),
                const SizedBox(height: 28),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: TextStyle(color: cInk, fontSize: 16, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: "Ví dụ: Lịch sử thế giới...",
                    hintStyle: TextStyle(color: cInk.withOpacity(0.28), fontSize: 15),
                    filled: true, fillColor: cSmoke,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cRust, width: 2)),
                  ),
                ),
                const SizedBox(height: 28),
                Row(children: [
                  Expanded(child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: cInk.withOpacity(0.15)),
                      ),
                    ),
                    child: Text("Hủy", style: TextStyle(color: cInk.withOpacity(0.45), fontWeight: FontWeight.w700)),
                  )),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cRust, elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () { _createNotebook(ctrl.text); Navigator.pop(context); },
                    child: const Text("Tạo hành trình →",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  )),
                ]),
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
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bg_knowledge.jpg'),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xBBFDF8F0),
                Color(0xDDF5EFE0),
                Color(0xF0EDE3D0),
              ],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _entranceAnim, curve: Curves.easeOut),
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(48, 16, 48, 60),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeroSection(),
                            const SizedBox(height: 36),
                            _buildSectionLabel(),
                            const SizedBox(height: 16),
                            _isLoading
                                ? _buildLoadingState()
                                : _buildJourneyList(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: cInk, borderRadius: BorderRadius.circular(9)),
            child: const Center(child: Icon(Icons.school_rounded, color: cGold, size: 20)),
          ),
          const SizedBox(width: 12),
          const Text("LEARNIFY", style: TextStyle(
              color: cInk, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 3.5)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cInk.withOpacity(0.07),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: cInk.withOpacity(0.12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: const BoxDecoration(color: cGold, shape: BoxShape.circle),
                  child: Center(child: Text(
                    widget.username.isNotEmpty ? widget.username[0].toUpperCase() : "?",
                    style: const TextStyle(color: cInk, fontWeight: FontWeight.w900, fontSize: 13),
                  )),
                ),
                const SizedBox(width: 9),
                Text(widget.username, style: const TextStyle(
                    color: cInk, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return AnimatedBuilder(
      animation: _entranceAnim,
      builder: (context, child) {
        final t = CurvedAnimation(
            parent: _entranceAnim,
            curve: const Interval(0.1, 0.7, curve: Curves.easeOutCubic));
        return Transform.translate(offset: Offset(0, 24 * (1 - t.value)), child: child);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: cGold.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cGold.withOpacity(0.45)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome, color: cGold, size: 13),
              SizedBox(width: 6),
              Text("Không gian tri thức của bạn",
                  style: TextStyle(color: cGold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ]),
          ),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              style: const TextStyle(color: cInk, fontSize: 46, fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -1),
              children: [
                const TextSpan(text: "Xin chào, "),
                TextSpan(
                  text: widget.username,
                  style: const TextStyle(color: cRust),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Mỗi notebook là một chuyến thám hiểm.\nHãy chọn hành trình của bạn.",
            style: TextStyle(color: cInk.withOpacity(0.5), fontSize: 15, height: 1.65),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel() {
    return Row(
      children: [
        Container(width: 3.5, height: 18, color: cRust),
        const SizedBox(width: 11),
        const Text("Hành trình của bạn",
            style: TextStyle(color: cInk, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2.2)),
        const SizedBox(width: 18),
        Expanded(child: Divider(color: cInk.withOpacity(0.1), thickness: 1)),
        const SizedBox(width: 18),
        _NewNotebookButton(onTap: _showCreateDialog),
      ],
    );
  }

  Widget _buildJourneyList() {
    if (_notebooks.isEmpty) return _buildEmptyState();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,       // 2 cột
        crossAxisSpacing: 16,    // khoảng cách ngang
        mainAxisSpacing: 0,      // card đã có bottom padding 12
        mainAxisExtent: 112,     // height card (100) + bottom padding (12)
      ),
      itemCount: _notebooks.length,
      itemBuilder: (_, i) => _JourneyCard(
        notebook: _notebooks[i],
        index: i,
        entranceController: _entranceAnim,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => HomeScreen(
            notebookId: _notebooks[i]['id'].toString(),
            notebookTitle: _notebooks[i]['title'],
          ),
        )),
        onRename: () => _showRenameDialog(_notebooks[i]['id'], _notebooks[i]['title']),
        onDelete: () => _showDeleteDialog(_notebooks[i]['id'], _notebooks[i]['title']),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Center(
        child: Column(children: [
          AnimatedBuilder(
            animation: _floatAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, -6 * _floatAnim.value), child: child),
            child: Icon(Icons.explore_outlined, size: 64, color: cInk.withOpacity(0.18)),
          ),
          const SizedBox(height: 18),
          Text("Chưa có hành trình nào",
              style: TextStyle(color: cInk.withOpacity(0.4), fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text("Tạo notebook đầu tiên để bắt đầu",
              style: TextStyle(color: cInk.withOpacity(0.28), fontSize: 13)),
          const SizedBox(height: 28),
          _NewNotebookButton(onTap: _showCreateDialog, large: true),
        ]),
      ),
    );
  }

  Widget _buildLoadingState() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 12,
        mainAxisExtent: 100,
      ),
      itemCount: 4,
      itemBuilder: (_, __) => const _ShimmerCard(),
    );
  }
}

class _JourneyCard extends StatefulWidget {
  final dynamic notebook;
  final int index;
  final AnimationController entranceController;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _JourneyCard({
    required this.notebook, 
    required this.index, 
    required this.entranceController, 
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_JourneyCard> createState() => _JourneyCardState();
}

class _JourneyCardState extends State<_JourneyCard> with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _hc;

  static const List<Color> _accents = [cRust, cForest, cSky, cLavender, cGold];
  static const List<IconData> _icons = [
    Icons.rocket_launch_rounded, Icons.biotech_rounded, Icons.calculate_rounded,
    Icons.psychology_rounded, Icons.history_edu_rounded,
  ];
  static const List<String> _tags = ["Khám phá", "Nghiên cứu", "Phân tích", "Tư duy", "Lịch sử"];

  @override
  void initState() {
    super.initState();
    _hc = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void dispose() { _hc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final accent = _accents[widget.index % _accents.length];
    final icon   = _icons[widget.index % _icons.length];
    final tag    = _tags[widget.index % _tags.length];
    final title  = widget.notebook['title'] as String? ?? 'Untitled';
    final date   = widget.notebook['created_at'].toString().split('T')[0];

    final delay = (widget.index * 0.08).clamp(0.0, 0.6);
    final anim  = CurvedAnimation(
      parent: widget.entranceController,
      curve: Interval(delay, (delay + 0.35).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 28 * (1 - anim.value)),
        child: Opacity(opacity: anim.value, child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: MouseRegion(
          onEnter: (_) { setState(() => _hovered = true); _hc.forward(); },
          onExit:  (_) { setState(() => _hovered = false); _hc.reverse(); },
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedBuilder(
              animation: _hc,
              builder: (_, child) => Transform.translate(offset: Offset(-3 * _hc.value, 0), child: child),
              child: Container(
                height: 100,
                // width tự co giãn theo cell của GridView
                decoration: BoxDecoration(
                  color: cCream,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _hovered ? accent.withOpacity(0.55) : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(_hovered ? 0.18 : 0.07),
                      blurRadius: 16, offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(children: [
                  Container(
                    width: 72,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16), bottomLeft: Radius.circular(16),
                      ),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(
                        (widget.index + 1).toString().padLeft(2, '0'),
                        style: TextStyle(color: Colors.white.withOpacity(0.28),
                            fontSize: 22, fontWeight: FontWeight.w900, height: 1),
                      ),
                      const SizedBox(height: 3),
                      Icon(icon, color: Colors.white.withOpacity(0.88), size: 18),
                    ]),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(tag, style: TextStyle(
                                color: accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                          ),
                          const SizedBox(height: 6),
                          Text(title,
                            style: const TextStyle(color: cInk, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedBuilder(
                            animation: _hc,
                            builder: (_, __) => Transform.translate(
                              offset: Offset(4 * _hc.value, 0),
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: _hovered ? accent : accent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.arrow_forward_rounded,
                                    color: _hovered ? Colors.white : accent, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(date, style: TextStyle(
                              color: cInk.withOpacity(0.3), fontSize: 11, fontWeight: FontWeight.w500)),
                        ]),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: cInk.withOpacity(0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          color: cCream,
                          onSelected: (value) {
                            if (value == 'rename') {
                              widget.onRename();
                            } else if (value == 'delete') {
                              widget.onDelete();
                            }
                          },
                          itemBuilder: (BuildContext context) => [
                            const PopupMenuItem<String>(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, color: cSky, size: 20),
                                  SizedBox(width: 8),
                                  Text('Đổi tên', style: TextStyle(color: cSky, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: cRust, size: 20),
                                  SizedBox(width: 8),
                                  Text('Xóa dự án', style: TextStyle(color: cRust, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewNotebookButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool large;
  const _NewNotebookButton({required this.onTap, this.large = false});

  @override
  State<_NewNotebookButton> createState() => _NewNotebookButtonState();
}

class _NewNotebookButtonState extends State<_NewNotebookButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
              horizontal: widget.large ? 28 : 18,
              vertical:  widget.large ? 14 : 9),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFA33E22) : cRust,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(
              color: cRust.withOpacity(_hovered ? 0.45 : 0.28),
              blurRadius: _hovered ? 16 : 10, offset: const Offset(0, 4),
            )],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.add, color: Colors.white, size: 15),
            const SizedBox(width: 7),
            Text("Notebook mới", style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: widget.large ? 15 : 12.5)),
          ]),
        ),
      ),
    );
  }
}

class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard();

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: 82,
        decoration: BoxDecoration(
          color: Color.lerp(cSmoke, cPaper, _c.value),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}