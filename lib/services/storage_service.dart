import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark_item.dart';
import '../models/history_item.dart';
import '../models/recent_document.dart';
import 'ai_service.dart';

class StorageService {
  static const double _epubBookmarkBucketSize = 0.25;

  int _compareRecentDocuments(RecentDocument a, RecentDocument b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;

    return b.openedAt.compareTo(a.openedAt);
  }

  Future<AiProvider> loadProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final savedProvider = prefs.getString('ai_provider') ?? 'openai';

    return savedProvider == 'deepseek'
        ? AiProvider.deepseek
        : AiProvider.openai;
  }

  Future<void> saveProvider(AiProvider provider) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'ai_provider',
      provider == AiProvider.deepseek ? 'deepseek' : 'openai',
    );
  }

  Future<bool> loadAutoTranslate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_translate') ?? false;
  }

  Future<void> saveAutoTranslate(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_translate', value);
  }

  Future<double> loadEpubFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('epub_font_size') ?? 18.0;
  }

  Future<void> saveEpubFontSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('epub_font_size', value);
  }

  Future<double> loadEpubHorizontalPadding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('epub_horizontal_padding') ?? 18.0;
  }

  Future<void> saveEpubHorizontalPadding(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('epub_horizontal_padding', value);
  }

  Future<double> loadEpubLineHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('epub_line_height') ?? 1.5;
  }

  Future<void> saveEpubLineHeight(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('epub_line_height', value);
  }

  Future<String> loadEpubReadingTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('epub_reading_theme') ?? 'white';
  }

  Future<void> saveEpubReadingTheme(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('epub_reading_theme', value);
  }

  Future<String> loadEpubFontFamily() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('epub_font_family') ?? 'default';
  }

  Future<void> saveEpubFontFamily(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('epub_font_family', value);
  }

  Future<String> loadEpubTextAlign() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('epub_text_align') ?? 'left';
  }

  Future<void> saveEpubTextAlign(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('epub_text_align', value);
  }

  Future<List<RecentDocument>> loadRecentDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('recent_documents') ?? [];

    final documents = raw
        .map((e) => RecentDocument.fromJson(jsonDecode(e)))
        .where((document) => document.path.isNotEmpty)
        .toList();

    documents.sort(_compareRecentDocuments);

    return documents.take(10).toList();
  }

  Future<void> saveRecentDocuments(List<RecentDocument> documents) async {
    final prefs = await SharedPreferences.getInstance();
    final sortedDocuments = [...documents]..sort(_compareRecentDocuments);
    final raw = sortedDocuments
        .take(10)
        .map((document) => jsonEncode(document.toJson()))
        .toList();

    await prefs.setStringList('recent_documents', raw);
  }

  Future<void> addRecentDocument(RecentDocument document) async {
    final documents = await loadRecentDocuments();
    final existingDocuments = documents
        .where((item) => item.path == document.path)
        .toList();
    final existingDocument = existingDocuments.isEmpty
        ? null
        : existingDocuments.first;
    final updatedDocument = document.copyWith(
      isPinned:
          document.isPinned ||
          (existingDocument != null && existingDocument.isPinned),
      thumbnailPath: document.thumbnailPath ?? existingDocument?.thumbnailPath,
      displayTitle: document.displayTitle ?? existingDocument?.displayTitle,
      author: document.author ?? existingDocument?.author,
    );
    final updatedDocuments = [
      updatedDocument,
      ...documents.where((item) => item.path != document.path),
    ];

    await saveRecentDocuments(updatedDocuments);
  }

  Future<void> updateRecentDocumentPinned(String path, bool isPinned) async {
    final documents = await loadRecentDocuments();
    final updatedDocuments = documents
        .map(
          (document) => document.path == path
              ? document.copyWith(isPinned: isPinned)
              : document,
        )
        .toList();

    await saveRecentDocuments(updatedDocuments);
  }

  Future<void> removeRecentDocument(String path) async {
    final documents = await loadRecentDocuments();
    await saveRecentDocuments(
      documents.where((document) => document.path != path).toList(),
    );
  }

  Future<void> replaceDocumentPath({
    required String oldPath,
    required String newPath,
    required String newName,
  }) async {
    final documents = await loadRecentDocuments();
    final updatedDocuments = documents
        .map(
          (document) => document.path == oldPath
              ? document.copyWith(path: newPath, name: newName)
              : document,
        )
        .toList();

    await saveRecentDocuments(updatedDocuments);

    final bookmarks = await getBookmarks();
    final updatedBookmarks = bookmarks
        .map(
          (bookmark) => bookmark.documentPath == oldPath
              ? bookmark.copyWithDocumentPath(
                  documentPath: newPath,
                  documentName: newName,
                )
              : bookmark,
        )
        .toList();

    await saveBookmarks(updatedBookmarks);
  }

  Future<void> clearRecentDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_documents');
  }

  Future<List<BookmarkItem>> getBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('bookmarks') ?? [];

    final bookmarks = raw
        .map((e) => BookmarkItem.fromJson(jsonDecode(e)))
        .where(
          (bookmark) =>
              bookmark.id.isNotEmpty && bookmark.documentPath.isNotEmpty,
        )
        .toList();

    bookmarks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return bookmarks;
  }

  Future<void> saveBookmarks(List<BookmarkItem> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final sortedBookmarks = [...bookmarks]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final raw = sortedBookmarks
        .map((bookmark) => jsonEncode(bookmark.toJson()))
        .toList();

    await prefs.setStringList('bookmarks', raw);
  }

  Future<void> addBookmark(BookmarkItem bookmark) async {
    final bookmarks = await getBookmarks();
    final updatedBookmarks = [
      bookmark,
      ...bookmarks.where((item) => !_isSameBookmark(item, bookmark)),
    ];

    await saveBookmarks(updatedBookmarks);
  }

  Future<void> removeBookmark(String id) async {
    final bookmarks = await getBookmarks();
    await saveBookmarks(bookmarks.where((item) => item.id != id).toList());
  }

  Future<void> removeBookmarksForDocument(String path) async {
    final bookmarks = await getBookmarks();
    await saveBookmarks(
      bookmarks.where((bookmark) => bookmark.documentPath != path).toList(),
    );
  }

  Future<void> updateBookmarkNote(String id, String? note) async {
    final cleanedNote = note?.trim();
    final bookmarks = await getBookmarks();
    final updatedBookmarks = bookmarks
        .map(
          (bookmark) => bookmark.id == id
              ? bookmark.copyWithNote(
                  cleanedNote == null || cleanedNote.isEmpty
                      ? null
                      : cleanedNote,
                )
              : bookmark,
        )
        .toList();

    await saveBookmarks(updatedBookmarks);
  }

  Future<bool> isBookmarked({
    required String documentPath,
    required String documentType,
    int? pageNumber,
    int? chapterIndex,
    double? epubPositionInChapter,
  }) async {
    final bookmarks = await getBookmarks();

    return bookmarks.any(
      (bookmark) =>
          bookmark.documentPath == documentPath &&
          bookmark.documentType == documentType &&
          _isSameBookmarkPosition(
            bookmark,
            documentType: documentType,
            pageNumber: pageNumber,
            chapterIndex: chapterIndex,
            epubPositionInChapter: epubPositionInChapter,
          ),
    );
  }

  bool _isSameBookmark(BookmarkItem a, BookmarkItem b) {
    if (a.documentPath != b.documentPath || a.documentType != b.documentType) {
      return false;
    }

    if (a.documentType == 'pdf') {
      return a.pageNumber == b.pageNumber;
    }

    if (a.documentType == 'epub') {
      return a.chapterIndex == b.chapterIndex &&
          _epubBookmarkBucket(a.epubPositionInChapter) ==
              _epubBookmarkBucket(b.epubPositionInChapter);
    }

    return a.documentPath == b.documentPath &&
        a.documentType == b.documentType &&
        a.pageNumber == b.pageNumber &&
        a.chapterIndex == b.chapterIndex;
  }

  bool _isSameBookmarkPosition(
    BookmarkItem bookmark, {
    required String documentType,
    int? pageNumber,
    int? chapterIndex,
    double? epubPositionInChapter,
  }) {
    if (documentType == 'pdf') {
      return bookmark.pageNumber == pageNumber;
    }

    if (documentType == 'epub') {
      return bookmark.chapterIndex == chapterIndex &&
          _epubBookmarkBucket(bookmark.epubPositionInChapter) ==
              _epubBookmarkBucket(epubPositionInChapter);
    }

    return bookmark.pageNumber == pageNumber &&
        bookmark.chapterIndex == chapterIndex;
  }

  int _epubBookmarkBucket(double? position) {
    final safePosition = (position ?? 0).clamp(0, double.infinity).toDouble();

    return (safePosition / _epubBookmarkBucketSize).round();
  }

  Future<String> makePdfStorageKey(String path) async {
    final file = File(path);
    final name = path.split(Platform.pathSeparator).last;
    final size = await file.length();

    return 'pdf_${name}_$size';
  }

  Future<int> loadSavedPage(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? 1;
  }

  Future<int?> loadSavedPageOrNull(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(key) ? prefs.getInt(key) : null;
  }

  Future<void> saveCurrentPage({
    required String pdfStorageKey,
    required int currentPage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(pdfStorageKey, currentPage);
  }

  Future<void> removeSavedPage(String pdfStorageKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pdfStorageKey);
  }

  String makeEpubStorageKey(String title) {
    final normalizedTitle = title.trim().toLowerCase();

    return 'epub_scroll_$normalizedTitle';
  }

  Future<double> loadSavedEpubScrollOffset(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(key) ?? 0;
  }

  Future<double?> loadSavedEpubScrollOffsetOrNull(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(key) ? prefs.getDouble(key) : null;
  }

  String _epubProgressKey(String epubStorageKey) {
    return '${epubStorageKey}_progress';
  }

  String _epubChapterIndexKey(String epubStorageKey) {
    return '${epubStorageKey}_chapter_index';
  }

  Future<int?> loadSavedEpubChapterIndex(String epubStorageKey) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _epubChapterIndexKey(epubStorageKey);

    return prefs.containsKey(key) ? prefs.getInt(key) : null;
  }

  Future<void> saveEpubChapterIndex({
    required String epubStorageKey,
    required int chapterIndex,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_epubChapterIndexKey(epubStorageKey), chapterIndex);
  }

  Future<int?> loadEpubProgress(String epubStorageKey) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _epubProgressKey(epubStorageKey);

    return prefs.containsKey(key) ? prefs.getInt(key) : null;
  }

  Future<void> saveEpubProgress(String epubStorageKey, int percent) async {
    final prefs = await SharedPreferences.getInstance();
    final clampedPercent = percent.clamp(0, 100);

    await prefs.setInt(_epubProgressKey(epubStorageKey), clampedPercent);
  }

  Future<void> removeEpubReadingPosition(String epubStorageKey) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(epubStorageKey);
    await prefs.remove(_epubProgressKey(epubStorageKey));
    await prefs.remove(_epubChapterIndexKey(epubStorageKey));
  }

  Future<void> saveEpubScrollOffset({
    required String epubStorageKey,
    required double scrollOffset,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(epubStorageKey, scrollOffset);
  }

  Future<List<HistoryItem>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('history') ?? [];

    return raw
        .map((e) => HistoryItem.fromJson(jsonDecode(e)))
        .toList()
        .reversed
        .toList();
  }

  Future<void> saveHistory(List<HistoryItem> history) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = history.reversed.map((e) => jsonEncode(e.toJson())).toList();

    await prefs.setStringList('history', raw);
  }

  Future<Map<String, String>> loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('translation_cache');

    if (raw == null) return {};

    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> saveCache(Map<String, String> cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('translation_cache', jsonEncode(cache));
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('translation_cache');
  }
}
