/// Простой value-объект для мотивирующих цитат. Хранится в JSON-ассетах.
class MotivationalQuote {
  const MotivationalQuote({required this.text, this.author});

  final String text;
  final String? author;

  factory MotivationalQuote.fromJson(Map<String, dynamic> json) =>
      MotivationalQuote(
        text: json['text'] as String,
        author: json['author'] as String?,
      );
}
