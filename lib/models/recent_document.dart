class RecentDocument {
  final String path;
  final String name;
  final String type;
  final DateTime openedAt;
  final bool isPinned;
  final String? thumbnailPath;

  const RecentDocument({
    required this.path,
    required this.name,
    required this.type,
    required this.openedAt,
    this.isPinned = false,
    this.thumbnailPath,
  });

  factory RecentDocument.fromJson(Map<String, dynamic> json) {
    return RecentDocument(
      path: json['path']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      openedAt:
          DateTime.tryParse(json['openedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isPinned: json['isPinned'] == true,
      thumbnailPath: _nullableStringFromJson(json['thumbnailPath']),
    );
  }

  static String? _nullableStringFromJson(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  RecentDocument copyWith({
    String? path,
    String? name,
    String? type,
    DateTime? openedAt,
    bool? isPinned,
    String? thumbnailPath,
  }) {
    return RecentDocument(
      path: path ?? this.path,
      name: name ?? this.name,
      type: type ?? this.type,
      openedAt: openedAt ?? this.openedAt,
      isPinned: isPinned ?? this.isPinned,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'type': type,
      'openedAt': openedAt.toIso8601String(),
      'isPinned': isPinned,
      'thumbnailPath': thumbnailPath,
    };
  }
}
