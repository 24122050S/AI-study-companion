import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';

class ConceptMapScreen extends StatefulWidget {
  final String username;
  final String notebookId;

  const ConceptMapScreen({super.key, required this.username, required this.notebookId});

  @override
  State<ConceptMapScreen> createState() => _ConceptMapScreenState();
}

class _ConceptMapScreenState extends State<ConceptMapScreen> {
  bool _isLoading = true;
  String _errorMessage = "";

  // Các biến của bộ công cụ vẽ Graph
  final Graph _graph = Graph()..isTree = true;
  final BuchheimWalkerConfiguration _builder = BuchheimWalkerConfiguration();
  
  List<dynamic> _nodesData = [];

  @override
  void initState() {
    super.initState();
    // Cấu hình khoảng cách và bố cục của Sơ đồ tư duy (Trên xuống Dưới)
    _builder
      ..siblingSeparation = (60)
      ..levelSeparation = (120)
      ..subtreeSeparation = (80)
      ..orientation = (BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM);
      
    _fetchConceptMap();
  }

  Future<void> _fetchConceptMap() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("${ApiConstants.baseUrl}/api/concept_map"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.username, "notebook_id": widget.notebookId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['status'] == 'success') {
          _nodesData = data['data']['nodes'];
          List<dynamic> edgesData = data['data']['edges'];
          
          Map<String, Node> nodeMap = {};
          
          // 1. Tạo các Đỉnh (Nodes)
          for (var n in _nodesData) {
            var node = Node.Id(n['id'].toString());
            nodeMap[n['id'].toString()] = node;
            _graph.addNode(node);
          }
          
          // 2. Nối các Đỉnh lại với nhau (Edges)
          for (var e in edgesData) {
             var fromNode = nodeMap[e['from'].toString()];
             var toNode = nodeMap[e['to'].toString()];
             if (fromNode != null && toNode != null) {
                _graph.addEdge(fromNode, toNode);
             }
          }
        } else {
          _errorMessage = data['message'] ?? "Lỗi không xác định";
        }
      }
    } catch (e) {
      _errorMessage = "Lỗi kết nối: $e";
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Khung thiết kế (UI) cho từng khối kiến thức
  Widget _buildNodeWidget(Node node) {
    String nodeId = node.key!.value.toString();
    var nodeData = _nodesData.firstWhere((n) => n['id'].toString() == nodeId, orElse: () => {"label": "N/A"});
    
    // Giao diện Khối kiến thức
    return Container(
       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
       constraints: const BoxConstraints(maxWidth: 200),
       decoration: BoxDecoration(
         color: Colors.white,
         borderRadius: BorderRadius.circular(15),
         border: Border.all(color: Colors.indigoAccent, width: 2),
         boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))]
       ),
       child: Text(
         nodeData['label'], 
         textAlign: TextAlign.center,
         style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)
       ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      appBar: AppBar(
        title: const Text("Sơ đồ Tư duy (AI Map)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchConceptMap,
            tooltip: "Tạo sơ đồ mới",
          )
        ],
      ),
      body: _isLoading 
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.indigo),
                SizedBox(height: 20),
                Text("AI đang vẽ lại Sơ đồ tư duy...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
              ],
            )
          )
        : _errorMessage.isNotEmpty
            ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
            : InteractiveViewer(
                constrained: false, // 🚀 Bắt buộc phải = false để có thể Zoom & Kéo tự do
                boundaryMargin: const EdgeInsets.all(300), // Không gian rộng bao la để kéo
                minScale: 0.1,
                maxScale: 3.0,
                child: Padding(
                  padding: const EdgeInsets.all(50.0),
                  child: GraphView(
                    graph: _graph,
                    algorithm: BuchheimWalkerAlgorithm(_builder, TreeEdgeRenderer(_builder)),
                    paint: Paint()
                      ..color = Colors.indigoAccent.withOpacity(0.5)
                      ..strokeWidth = 3
                      ..style = PaintingStyle.stroke,
                    builder: (Node node) => _buildNodeWidget(node),
                  ),
                ),
              ),
    );
  }
}