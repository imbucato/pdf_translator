import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:html_unescape/html_unescape.dart';

class EpubChapterData {
  final String title;
  final String text;

  EpubChapterData({required this.title, required this.text});
}

class EpubBookData {
  final String title;
  final List<EpubChapterData> chapters;

  EpubBookData({required this.title, required this.chapters});
}

class EpubService {
  static final HtmlUnescape _unescape = HtmlUnescape();

  Future<EpubBookData> readEpub(File file) async {
    final bytes = await file.readAsBytes();
    final book = await EpubReader.readBook(bytes);

    final title = book.Title ?? 'EPUB senza titolo';

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

    return EpubBookData(title: title, chapters: chapters);
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
