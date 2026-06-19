import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/bookmark_item.dart';
import '../services/document_import_service.dart';
import '../services/epub_service.dart';
import '../services/pdf_thumbnail_service.dart';
import '../services/storage_service.dart';
import '../services/text_cleaner_service.dart';
import '../widgets/document_thumbnail.dart';
import 'epub_reader_page.dart';
import 'pdf_translator_page.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  final StorageService _storageService = StorageService();
  final DocumentImportService _documentImportService = DocumentImportService();
  final Set<String> _pendingPdfThumbnailPaths = {};

  List<BookmarkItem> _bookmarks = [];
  Map<String, String> _bookmarkThumbnailPaths = {};
  Map<String, String> _bookmarkDisplayTitles = {};
  Map<String, String> _bookmarkAuthors = {};
  bool _isLoading = true;
  bool _isOpeningDocument = false;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final bookmarks = await _storageService.getBookmarks();

    if (!mounted) return;

    setState(() {
      _bookmarks = bookmarks;
      _isLoading = false;
    });

    await _loadBookmarkThumbnails(bookmarks);
  }

  Future<void> _loadBookmarkThumbnails(List<BookmarkItem> bookmarks) async {
    final recentDocuments = await _storageService.loadRecentDocuments();
    final recentThumbnailPaths = {
      for (final document in recentDocuments)
        if (_thumbnailPathExists(document.thumbnailPath))
          document.path: document.thumbnailPath!,
    };
    final recentDisplayTitles = {
      for (final document in recentDocuments)
        if (document.displayTitle?.trim().isNotEmpty == true)
          document.path: document.displayTitle!,
    };
    final recentAuthors = {
      for (final document in recentDocuments)
        if (document.author?.trim().isNotEmpty == true)
          document.path: document.author!,
    };
    final thumbnailPaths = <String, String>{};
    final displayTitles = <String, String>{};
    final authors = <String, String>{};
    final epubService = EpubService();

    for (final bookmark in bookmarks) {
      final bookmarkThumbnailPath = bookmark.thumbnailPath;
      final bookmarkDisplayTitle = bookmark.displayTitle;
      final bookmarkAuthor = bookmark.author;
      final recentDisplayTitle = recentDisplayTitles[bookmark.documentPath];
      final recentAuthor = recentAuthors[bookmark.documentPath];

      if (bookmarkDisplayTitle?.trim().isNotEmpty == true) {
        displayTitles[bookmark.id] = bookmarkDisplayTitle!;
      } else if (recentDisplayTitle?.trim().isNotEmpty == true) {
        displayTitles[bookmark.id] = recentDisplayTitle!;
      }

      if (bookmarkAuthor?.trim().isNotEmpty == true) {
        authors[bookmark.id] = bookmarkAuthor!;
      } else if (recentAuthor?.trim().isNotEmpty == true) {
        authors[bookmark.id] = recentAuthor!;
      }

      if (_thumbnailPathExists(bookmarkThumbnailPath)) {
        thumbnailPaths[bookmark.id] = bookmarkThumbnailPath!;
      }

      final recentThumbnailPath = recentThumbnailPaths[bookmark.documentPath];

      if (!thumbnailPaths.containsKey(bookmark.id) &&
          _thumbnailPathExists(recentThumbnailPath)) {
        thumbnailPaths[bookmark.id] = recentThumbnailPath!;
      }

      final type = bookmark.documentType.toLowerCase();

      if (!thumbnailPaths.containsKey(bookmark.id) && type == 'pdf') {
        final thumbnailPath = await PdfThumbnailService()
            .cachedThumbnailPathForFile(File(bookmark.documentPath));

        if (_thumbnailPathExists(thumbnailPath)) {
          thumbnailPaths[bookmark.id] = thumbnailPath!;
        } else {
          _schedulePdfThumbnailGeneration(bookmark.documentPath);
        }
      }

      if (!thumbnailPaths.containsKey(bookmark.id) && type == 'epub') {
        final coverPath = await epubService.cacheCoverForFile(
          File(bookmark.documentPath),
        );

        if (_thumbnailPathExists(coverPath)) {
          thumbnailPaths[bookmark.id] = coverPath!;
        }
      }

      if (!displayTitles.containsKey(bookmark.id)) {
        if (type == 'epub') {
          try {
            final book = await epubService.readEpub(
              File(bookmark.documentPath),
            );
            displayTitles[bookmark.id] = _epubDisplayTitle(
              book,
              bookmark.documentPath,
            );

            if (book.author?.trim().isNotEmpty == true) {
              authors[bookmark.id] = book.author!;
            }
          } catch (_) {
            displayTitles[bookmark.id] = _cleanDocumentTitle(
              bookmark.documentName,
            );
          }
        } else {
          displayTitles[bookmark.id] = _cleanDocumentTitle(
            bookmark.documentName,
          );
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _bookmarkThumbnailPaths = thumbnailPaths;
      _bookmarkDisplayTitles = displayTitles;
      _bookmarkAuthors = authors;
    });
  }

  bool _thumbnailPathExists(String? path) {
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  void _schedulePdfThumbnailGeneration(String path) {
    if (!_pendingPdfThumbnailPaths.add(path)) return;

    unawaited(() async {
      try {
        final thumbnailPath = await PdfThumbnailService().cacheThumbnailForFile(
          File(path),
        );

        if (thumbnailPath == null || !mounted) return;

        setState(() {
          _bookmarkThumbnailPaths = {
            ..._bookmarkThumbnailPaths,
            for (final bookmark in _bookmarks)
              if (bookmark.documentPath == path) bookmark.id: thumbnailPath,
          };
        });
      } finally {
        _pendingPdfThumbnailPaths.remove(path);
      }
    }());
  }

  Future<void> _removeBookmark(BookmarkItem bookmark) async {
    await _storageService.removeBookmark(bookmark.id);
    await _loadBookmarks();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Segnalibro eliminato')));
  }

  Future<void> _openBookmark(BookmarkItem bookmark) async {
    var effectiveBookmark = bookmark;
    var file = File(effectiveBookmark.documentPath);

    _debugLogBookmarkOpen(effectiveBookmark);

    if (!file.existsSync()) {
      await _handleMissingBookmarkDocument(effectiveBookmark);
      return;
    }

    if (_documentImportService.looksTemporary(effectiveBookmark.documentPath)) {
      final importedFile = await _documentImportService.importDocument(
        effectiveBookmark.documentPath,
      );

      if (importedFile.path != effectiveBookmark.documentPath) {
        final newName = _documentNameFromPath(importedFile.path);
        await _storageService.replaceDocumentPath(
          oldPath: effectiveBookmark.documentPath,
          newPath: importedFile.path,
          newName: newName,
        );
        effectiveBookmark = effectiveBookmark.copyWithDocumentPath(
          documentPath: importedFile.path,
          documentName: newName,
        );
        file = importedFile;
      }
    }

    if (!mounted) return;

    if (effectiveBookmark.documentType == 'pdf') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfTranslatorPage(
            initialPdfPath: effectiveBookmark.documentPath,
            initialPageNumber: effectiveBookmark.pageNumber,
          ),
        ),
      );

      if (!mounted) return;
      await _loadBookmarks();
      return;
    }

    if (effectiveBookmark.documentType == 'epub') {
      await _openEpubBookmark(effectiveBookmark, file);
    }
  }

  void _debugLogBookmarkOpen(BookmarkItem bookmark) {
    if (!kDebugMode) return;

    final path = bookmark.documentPath;
    final normalizedPath = path.replaceAll('\\', '/').toLowerCase();
    final title = bookmark.displayTitle?.trim().isNotEmpty == true
        ? bookmark.displayTitle!.trim()
        : bookmark.documentName;

    debugPrint(
      '[AI_READER_DOC_OPEN][segnalibri] title="$title" '
      'path="$path" exists=${File(path).existsSync()} '
      'cache=${normalizedPath.contains('/cache/')} '
      'filePicker=${normalizedPath.contains('file_picker')} '
      'dataUser0=${normalizedPath.contains('/data/user/0/')} '
      'appPath=${normalizedPath.contains('pdf_translator')}',
    );
  }

  Future<void> _handleMissingBookmarkDocument(BookmarkItem bookmark) async {
    if (!mounted) return;

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('File non trovato'),
          content: const Text(
            'Il documento potrebbe essere stato spostato, rinominato o eliminato.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Rimuovi dalla lista'),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true) return;

    try {
      await _storageService.removeRecentDocument(bookmark.documentPath);
      await _storageService.removeBookmarksForDocument(bookmark.documentPath);
      await _loadBookmarks();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documento rimosso dalla lista')),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Non sono riuscito a rimuovere il riferimento.'),
        ),
      );
    }
  }

  Future<void> _openEpubBookmark(BookmarkItem bookmark, File file) async {
    setState(() {
      _isOpeningDocument = true;
    });

    try {
      final book = await EpubService().readEpub(file);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EpubReaderPage(
            book: book,
            documentPath: bookmark.documentPath,
            initialChapterIndex: bookmark.chapterIndex,
            initialChapterAlignment:
                bookmark.epubAlignment ??
                (bookmark.epubPositionInChapter == null
                    ? null
                    : -bookmark.epubPositionInChapter!),
          ),
        ),
      );

      if (!mounted) return;
      await _loadBookmarks();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore apertura EPUB: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningDocument = false;
        });
      }
    }
  }

  String _formatCreatedAt(DateTime createdAt) {
    if (createdAt.millisecondsSinceEpoch == 0) return '';

    final day = createdAt.day.toString().padLeft(2, '0');
    final month = createdAt.month.toString().padLeft(2, '0');
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');

    return '$day/$month $hour:$minute';
  }

  String _typeLabel(BookmarkItem bookmark) {
    return bookmark.documentType.toLowerCase() == 'pdf' ? 'PDF' : 'EPUB';
  }

  String _cleanDocumentTitle(String name) {
    return TextCleanerService.cleanDocumentTitle(name);
  }

  String _cleanDocumentTitleFromPath(String path) {
    return _cleanDocumentTitle(path.split(Platform.pathSeparator).last);
  }

  String _documentNameFromPath(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  String _epubDisplayTitle(EpubBookData book, String path) {
    return book.title == 'EPUB senza titolo'
        ? _cleanDocumentTitleFromPath(path)
        : book.title;
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.bookmarks_outlined,
                color: colorScheme.onSecondaryContainer,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nessun segnalibro',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Salva una pagina PDF o un capitolo EPUB dal reader',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookmarkCard(BuildContext context, BookmarkItem bookmark) {
    final colorScheme = Theme.of(context).colorScheme;
    final createdAt = _formatCreatedAt(bookmark.createdAt);
    final displayTitle = bookmark.documentType.toLowerCase() == 'pdf'
        ? _cleanDocumentTitle(
            bookmark.displayTitle ??
                _bookmarkDisplayTitles[bookmark.id] ??
                bookmark.documentName,
          )
        : bookmark.displayTitle ??
              _bookmarkDisplayTitles[bookmark.id] ??
              _cleanDocumentTitle(bookmark.documentName);
    final author = bookmark.author ?? _bookmarkAuthors[bookmark.id];

    return Card(
      elevation: 1.5,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.10),
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        leading: DocumentThumbnail(
          documentType: bookmark.documentType,
          thumbnailPath:
              bookmark.thumbnailPath ?? _bookmarkThumbnailPaths[bookmark.id],
        ),
        title: Text(
          displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (author != null && author.isNotEmpty) ...[
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                bookmark.positionLabel.isNotEmpty
                    ? bookmark.positionLabel
                    : _typeLabel(bookmark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (bookmark.note?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 3),
                Text(
                  bookmark.note!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (createdAt.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  '${_typeLabel(bookmark)} - $createdAt',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: 'Elimina segnalibro',
          icon: const Icon(Icons.delete_outline),
          onPressed: _isOpeningDocument
              ? null
              : () => _removeBookmark(bookmark),
        ),
        onTap: _isOpeningDocument ? null : () => _openBookmark(bookmark),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Segnalibri')),
      backgroundColor: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.045),
        colorScheme.surface,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _bookmarks.isEmpty
            ? _buildEmptyState(context)
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      children: _bookmarks
                          .map(
                            (bookmark) => _buildBookmarkCard(context, bookmark),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
