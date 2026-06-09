class RecentDocument {
  final String path;
  final String name;
  final String type;
  final DateTime openedAt;

  const RecentDocument({
    required this.path,
    required this.name,
    required this.type,
    required this.openedAt,
  });

  factory RecentDocument.fromJson(Map<String, dynamic> json) {
    return RecentDocument(
      path: json['path']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      openedAt:
          DateTime.tryParse(json['openedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'type': type,
      'openedAt': openedAt.toIso8601String(),
    };
  }
}
