import 'dart:io';

import 'package:flutter/material.dart';

import '../models/bookmark_item.dart';
import '../services/epub_service.dart';
import '../services/storage_service.dart';
import 'epub_reader_page.dart';
import 'pdf_translator_page.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  final StorageService _storageService = StorageService();

  List<BookmarkItem> _bookmarks = [];
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
    final file = File(bookmark.documentPath);

    if (!file.existsSync()) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File non trovato')));
      return;
    }

    if (bookmark.documentType == 'pdf') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfTranslatorPage(
            initialPdfPath: bookmark.documentPath,
            initialPageNumber: bookmark.pageNumber,
          ),
        ),
      );

      if (!mounted) return;
      await _loadBookmarks();
      return;
    }

    if (bookmark.documentType == 'epub') {
      await _openEpubBookmark(bookmark, file);
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
            initialChapterAlignment: bookmark.epubAlignment,
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
    final isPdf = bookmark.documentType.toLowerCase() == 'pdf';
    final createdAt = _formatCreatedAt(bookmark.createdAt);

    return Card(
      elevation: 1.5,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.10),
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isPdf
                ? colorScheme.primaryContainer
                : colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            isPdf ? Icons.picture_as_pdf : Icons.menu_book,
            color: isPdf
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(
          bookmark.documentName,
          maxLines: 1,
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
              Text(
                bookmark.positionLabel.isNotEmpty
                    ? bookmark.positionLabel
                    : _typeLabel(bookmark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
