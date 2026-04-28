class HistoryItem {
  final String pdfKey;
  final String action;
  final String provider;
  final String original;
  final String result;
  final int page;
  final DateTime date;

  HistoryItem({
    required this.pdfKey,
    required this.action,
    required this.provider,
    required this.original,
    required this.result,
    required this.page,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'pdfKey': pdfKey,
    'action': action,
    'provider': provider,
    'original': original,
    'result': result,
    'page': page,
    'date': date.toIso8601String(),
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      pdfKey: json['pdfKey'] ?? '',
      action: json['action'] ?? '',
      provider: json['provider'] ?? 'OpenAI',
      original: json['original'] ?? '',
      result: json['result'] ?? '',
      page: json['page'] ?? 1,
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
    );
  }
}
