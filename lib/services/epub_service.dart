import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:path_provider/path_provider.dart';

class EpubChapterData {
  final String title;
  final String text;

  EpubChapterData({required this.title, required this.text});
}

class EpubBookData {
  final String title;
  final List<EpubChapterData> chapters;
  final String? coverPath;

  EpubBookData({required this.title, required this.chapters, this.coverPath});
}

class EpubService {
  static final HtmlUnescape _unescape = HtmlUnescape();

  Future<EpubBookData> readEpub(File file) async {
    final bytes = await file.readAsBytes();
    final book = await EpubReader.readBook(bytes);

    final title = book.Title ?? 'EPUB senza titolo';
    final coverPath = await _tryCacheCoverImage(file, book);

    final chapters = <EpubChapterData>[];

    void collectChapters(List<EpubChapter>? epubChapters) {
      if (epubChapters == null) return;

      for (final chapter in epubChapters) {
        final chapterTitle = chapter.Title?.trim().isNotEmpty == true
            ? chapter.Title!.trim()
            : 'Capitolo ${chapters.length + 1}';

        final html = chapter.HtmlContent ?? '';
        final text = _htmlToPlainText(html);

        if (text.trim().isNotEmpty) {
          chapters.add(EpubChapterData(title: chapterTitle, text: text));
        }

        collectChapters(chapter.SubChapters);
      }
    }

    collectChapters(book.Chapters);

    return EpubBookData(title: title, chapters: chapters, coverPath: coverPath);
  }

  Future<String?> cacheCoverForFile(File file) async {
    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      final book = await EpubReader.readBook(bytes);
      return _tryCacheCoverImage(file, book);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _tryCacheCoverImage(File file, EpubBook book) async {
    try {
      return _cacheCoverImage(file, book);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _cacheCoverImage(File file, EpubBook book) async {
    final cachedFile = await _coverCacheFile(file, book);

    if (await cachedFile.exists()) return cachedFile.path;

    final coverBytes = _coverImageBytes(book);

    if (coverBytes == null || coverBytes.isEmpty) return null;

    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes(coverBytes, flush: true);

    return cachedFile.path;
  }

  Future<File> _coverCacheFile(File file, EpubBook book) async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(
      '${appDir.path}${Platform.pathSeparator}epub_covers',
    );
    final stat = await file.stat();
    final key = _stableCacheKey(
      '${file.path}|${stat.modified.millisecondsSinceEpoch}|${stat.size}',
    );
    final extension = _coverFileExtension(book) ?? 'jpg';

    return File('${cacheDir.path}${Platform.pathSeparator}$key.$extension');
  }

  List<int>? _coverImageBytes(EpubBook book) {
    final coverItem = _coverManifestItem(book);
    final href = coverItem?.Href;

    if (href == null || href.isEmpty) return null;
    if (!_isSupportedCoverMimeType(coverItem?.MediaType)) return null;

    return book.Content?.Images?[href]?.Content;
  }

  EpubManifestItem? _coverManifestItem(EpubBook book) {
    final manifestItems = book.Schema?.Package?.Manifest?.Items;

    if (manifestItems == null || manifestItems.isEmpty) return null;

    String? coverId;
    final metaItems = book.Schema?.Package?.Metadata?.MetaItems;

    if (metaItems != null) {
      for (final item in metaItems) {
        if (item.Name?.toLowerCase() == 'cover') {
          coverId = item.Content;
          break;
        }
      }
    }

    if (coverId != null && coverId.isNotEmpty) {
      for (final item in manifestItems) {
        if (item.Id?.toLowerCase() == coverId.toLowerCase()) return item;
      }
    }

    for (final item in manifestItems) {
      final properties = item.Properties?.toLowerCase() ?? '';
      if (properties.split(RegExp(r'\s+')).contains('cover-image')) {
        return item;
      }
    }

    return null;
  }

  String? _coverFileExtension(EpubBook book) {
    final mimeType = _coverManifestItem(book)?.MediaType?.toLowerCase();

    switch (mimeType) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/bmp':
        return 'bmp';
      default:
        return null;
    }
  }

  bool _isSupportedCoverMimeType(String? mimeType) {
    return const {
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/bmp',
    }.contains(mimeType?.toLowerCase());
  }

  String _stableCacheKey(String value) {
    var hash = 0x811c9dc5;

    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }

    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _htmlToPlainText(String html) {
    var text = html;

    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    text = text.replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n\n');

    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = _unescape.convert(text);

    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');

    return text.trim();
  }
}
