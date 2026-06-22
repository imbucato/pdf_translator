import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/wikipedia_result.dart';

class WikipediaService {
  static const int maxQueryLength = 120;
  static const Duration _timeout = Duration(seconds: 8);

  String cleanQuery(String input) {
    var query = input.trim();
    query = query.replaceAll(RegExp(r'\s*\n+\s*'), ' ');
    query = query.replaceAll(RegExp(r'\s+'), ' ');

    if (query.length > maxQueryLength) {
      query = query.substring(0, maxQueryLength).trim();
    }

    return query;
  }

  Future<WikipediaResult?> searchSummary(
    String query, {
    String language = 'it',
  }) async {
    final cleanedQuery = cleanQuery(query);
    if (cleanedQuery.isEmpty) return null;

    try {
      final title = await _searchTitle(cleanedQuery, language: language);
      if (title == null || title.trim().isEmpty) return null;

      return _fetchSummary(title, language: language);
    } on TimeoutException {
      throw Exception(
        'Wikipedia non ha risposto in tempo. Controlla la connessione e riprova.',
      );
    } on FormatException {
      throw Exception(
        'Risposta Wikipedia non riconosciuta. Riprova tra qualche minuto.',
      );
    } on http.ClientException {
      throw Exception(
        'Connessione non disponibile. Controlla la rete e riprova.',
      );
    }
  }

  Future<WikipediaResult?> searchSummaryWithFallback(String query) async {
    final italianResult = await searchSummary(query, language: 'it');
    if (_isValidResult(italianResult)) return italianResult;

    return searchSummary(query, language: 'en');
  }

  bool _isValidResult(WikipediaResult? result) {
    return result != null &&
        result.title.trim().isNotEmpty &&
        result.extract.trim().isNotEmpty;
  }

  Future<String?> _searchTitle(String query, {required String language}) async {
    final uri = Uri.https('$language.wikipedia.org', '/w/api.php', {
      'action': 'opensearch',
      'search': query,
      'limit': '1',
      'namespace': '0',
      'format': 'json',
    });

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Wikipedia ha risposto con errore ${response.statusCode}. Riprova piu tardi.',
      );
    }

    final data = jsonDecode(response.body);
    if (data is! List || data.length < 2 || data[1] is! List) return null;

    final titles = data[1] as List;
    if (titles.isEmpty) return null;

    final title = titles.first;
    return title is String ? title : null;
  }

  Future<WikipediaResult?> _fetchSummary(
    String title, {
    required String language,
  }) async {
    final uri = Uri.parse(
      'https://$language.wikipedia.org/api/rest_v1/page/summary/'
      '${Uri.encodeComponent(title)}',
    );

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 404) return null;

    if (response.statusCode != 200) {
      throw Exception(
        'Wikipedia ha risposto con errore ${response.statusCode}. Riprova piu tardi.',
      );
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) return null;

    final normalizedTitle = data['title'];
    final extract = data['extract'];
    final contentUrls = data['content_urls'];
    final desktopUrl = contentUrls is Map<String, dynamic>
        ? contentUrls['desktop']
        : null;
    final pageUrl = desktopUrl is Map<String, dynamic>
        ? desktopUrl['page']
        : null;
    final thumbnail = data['thumbnail'];
    final thumbnailUrl = thumbnail is Map<String, dynamic>
        ? thumbnail['source']
        : null;

    if (normalizedTitle is! String ||
        extract is! String ||
        pageUrl is! String ||
        extract.trim().isEmpty) {
      return null;
    }

    return WikipediaResult(
      title: normalizedTitle,
      extract: extract,
      language: language,
      pageUrl: pageUrl,
      thumbnailUrl: thumbnailUrl is String ? thumbnailUrl : null,
    );
  }
}
