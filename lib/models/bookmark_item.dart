class BookmarkItem {
  final String id;
  final String documentPath;
  final String documentName;
  final String documentType;
  final DateTime createdAt;
  final int? pageNumber;
  final int? chapterIndex;
  final String? chapterTitle;
  final double? epubAlignment;
  final String positionLabel;

  const BookmarkItem({
    required this.id,
    required this.documentPath,
    required this.documentName,
    required this.documentType,
    required this.createdAt,
    required this.positionLabel,
    this.pageNumber,
    this.chapterIndex,
    this.chapterTitle,
    this.epubAlignment,
  });

  factory BookmarkItem.fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      id: json['id']?.toString() ?? '',
      documentPath: json['documentPath']?.toString() ?? '',
      documentName: json['documentName']?.toString() ?? '',
      documentType: json['documentType']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      pageNumber: _intFromJson(json['pageNumber']),
      chapterIndex: _intFromJson(json['chapterIndex']),
      chapterTitle: json['chapterTitle']?.toString(),
      epubAlignment: _doubleFromJson(json['epubAlignment']),
      positionLabel: json['positionLabel']?.toString() ?? '',
    );
  }

  static int? _intFromJson(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _doubleFromJson(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'documentPath': documentPath,
      'documentName': documentName,
      'documentType': documentType,
      'createdAt': createdAt.toIso8601String(),
      'pageNumber': pageNumber,
      'chapterIndex': chapterIndex,
      'chapterTitle': chapterTitle,
      'epubAlignment': epubAlignment,
      'positionLabel': positionLabel,
    };
  }
}
