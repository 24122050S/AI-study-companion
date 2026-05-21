import 'package:flutter/material.dart';

class QuizReviewScreen extends StatelessWidget {
  final List<dynamic> questions; // Danh sách câu hỏi AI trả về
  final Map<int, String> userAnswers; // Các đáp án user đã bấm chọn

  const QuizReviewScreen({
    super.key,
    required this.questions,
    required this.userAnswers,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Xem lại bài làm", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final q = questions[index];
          final String correctAnswer = q['answer'];
          final String? selectedAnswer = userAnswers[index];
          
          // Kiểm tra đúng sai
          final bool isCorrect = selectedAnswer == correctAnswer;
          final bool isSkipped = selectedAnswer == null;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isCorrect ? Colors.green : (isSkipped ? Colors.orange : Colors.red),
                width: 1.5,
              ),
            ),
            color: isCorrect ? Colors.green[50] : (isSkipped ? Colors.orange[50] : Colors.red[50]),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Câu hỏi
                  Text(
                    "Câu ${index + 1}: ${q['question']}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  
                  // Đáp án đã chọn
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isCorrect ? Icons.check_circle : (isSkipped ? Icons.help_outline : Icons.cancel),
                        color: isCorrect ? Colors.green : (isSkipped ? Colors.orange : Colors.red),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Bạn chọn: ${selectedAnswer ?? 'Bỏ trống'}",
                          style: TextStyle(
                            color: isCorrect ? Colors.green[700] : (isSkipped ? Colors.orange[700] : Colors.red[700]),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Hiện đáp án đúng nếu làm sai hoặc bỏ trống
                  if (!isCorrect) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Đáp án đúng: $correctAnswer",
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ]
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          ),
          onPressed: () {
            // Thoát màn hình chữa bài, về thẳng trang chủ
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Text("Về trang chủ", style: TextStyle(fontSize: 18, color: Colors.white)),
        ),
      ),
    );
  }
}