class RecentDocument {
  final String path;
  final String name;
  final String type;
  final DateTime openedAt;
  final bool isPinned;

  const RecentDocument({
    required this.path,
    required this.name,
    required this.type,
    required this.openedAt,
    this.isPinned = false,
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
    );
  }

  RecentDocument copyWith({
    String? path,
    String? name,
    String? type,
    DateTime? openedAt,
    bool? isPinned,
  }) {
    return RecentDocument(
      path: path ?? this.path,
      name: name ?? this.name,
      type: type ?? this.type,
      openedAt: openedAt ?? this.openedAt,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'type': type,
      'openedAt': openedAt.toIso8601String(),
      'isPinned': isPinned,
    };
  }
}
