import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_item.dart';
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
