import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_item.dart';
import '../models/recent_document.dart';
import 'ai_service.dart';

class StorageService {
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
    return prefs.getString('epub_reading_theme') ?? 'light';
  }

  Future<void> saveEpubReadingTheme(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('epub_reading_theme', value);
  }

  Future<List<RecentDocument>> loadRecentDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('recent_documents') ?? [];

    final documents = raw
        .map((e) => RecentDocument.fromJson(jsonDecode(e)))
        .where((document) => document.path.isNotEmpty)
        .toList();

    documents.sort((a, b) => b.openedAt.compareTo(a.openedAt));

    return documents.take(10).toList();
  }

  Future<void> saveRecentDocuments(List<RecentDocument> documents) async {
    final prefs = await SharedPreferences.getInstance();
    final sortedDocuments = [...documents]
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    final raw = sortedDocuments
        .take(10)
        .map((document) => jsonEncode(document.toJson()))
        .toList();

    await prefs.setStringList('recent_documents', raw);
  }

  Future<void> addRecentDocument(RecentDocument document) async {
    final documents = await loadRecentDocuments();
    final updatedDocuments = [
      document,
      ...documents.where((item) => item.path != document.path),
    ];

    await saveRecentDocuments(updatedDocuments);
  }

  Future<void> removeRecentDocument(String path) async {
    final documents = await loadRecentDocuments();
    await saveRecentDocuments(
      documents.where((document) => document.path != path).toList(),
    );
  }

  Future<void> clearRecentDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_documents');
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
