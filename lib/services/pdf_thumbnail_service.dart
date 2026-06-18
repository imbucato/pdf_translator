import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';

class PdfThumbnailService {
  static const int _maxWidth = 180;
  static const int _maxHeight = 240;

  Future<String?> cachedThumbnailPathForFile(File file) async {
    if (!await file.exists()) return null;

    try {
      final cachedFile = await _thumbnailCacheFile(file);
      return await cachedFile.exists() ? cachedFile.path : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> cacheThumbnailForFile(File file) async {
    if (!await file.exists()) return null;

    try {
      final cachedFile = await _thumbnailCacheFile(file);
      if (await cachedFile.exists()) return cachedFile.path;

      final pngBytes = await _renderFirstPage(file);
      if (pngBytes == null || pngBytes.isEmpty) return null;

      await cachedFile.parent.create(recursive: true);
      await cachedFile.writeAsBytes(pngBytes, flush: true);

      return cachedFile.path;
    } catch (_) {
      return null;
    }
  }

  Future<File> _thumbnailCacheFile(File file) async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(
      '${appDir.path}${Platform.pathSeparator}pdf_thumbnails',
    );
    final stat = await file.stat();
    final key = _stableCacheKey(
      '${file.path}|${stat.modified.millisecondsSinceEpoch}|${stat.size}',
    );

    return File('${cacheDir.path}${Platform.pathSeparator}$key.png');
  }

  Future<List<int>?> _renderFirstPage(File file) async {
    final documentId = _stableCacheKey(
      '${file.path}|${DateTime.now().microsecondsSinceEpoch}',
    );
    final platform = PdfViewerPlatform.instance;

    try {
      final pageCount = await platform.loadPdfFromFile(file.path, documentId);
      if ((int.tryParse(pageCount ?? '') ?? 0) <= 0) return null;

      final pageWidths = await platform.getPagesWidth(documentId);
      final pageHeights = await platform.getPagesHeight(documentId);

      if (pageWidths == null ||
          pageHeights == null ||
          pageWidths.isEmpty ||
          pageHeights.isEmpty) {
        return null;
      }

      final pageWidth = _numberToDouble(pageWidths.first);
      final pageHeight = _numberToDouble(pageHeights.first);

      if (pageWidth <= 0 || pageHeight <= 0) return null;

      final scale = math.min(_maxWidth / pageWidth, _maxHeight / pageHeight);
      final width = math.max(1, (pageWidth * scale).round());
      final height = math.max(1, (pageHeight * scale).round());
      final pixels = await platform.getPage(1, width, height, documentId);

      if (pixels == null || pixels.length < width * height * 4) return null;

      final thumbnailImage = image.Image.fromBytes(
        width,
        height,
        pixels,
        format: image.Format.rgba,
      );

      return image.encodePng(thumbnailImage);
    } finally {
      try {
        await platform.closeDocument(documentId);
      } catch (_) {}
    }
  }

  double _numberToDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _stableCacheKey(String value) {
    var hash = 0x811c9dc5;

    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }

    return hash.toRadixString(16).padLeft(8, '0');
  }
}
