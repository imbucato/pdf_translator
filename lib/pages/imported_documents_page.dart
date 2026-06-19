import 'dart:io';

import 'package:flutter/material.dart';

import '../models/recent_document.dart';
import '../services/document_import_service.dart';
import '../services/epub_service.dart';
import '../services/storage_service.dart';
import '../services/text_cleaner_service.dart';
import 'epub_reader_page.dart';
import 'pdf_translator_page.dart';

class ImportedDocumentsPage extends StatefulWidget {
  const ImportedDocumentsPage({super.key});

  @override
  State<ImportedDocumentsPage> createState() => _ImportedDocumentsPageState();
}

class _ImportedDocumentsPageState extends State<ImportedDocumentsPage> {
  final DocumentImportService _documentImportService = DocumentImportService();
  final StorageService _storageService = StorageService();

  List<File> _documents = [];
  bool _isLoading = true;
  bool _isBusy = false;

  int get _totalBytes {
    return _documents.fold<int>(0, (total, file) => total + file.lengthSync());
  }

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    final documents = await _documentImportService.importedDocuments();

    if (!mounted) return;

    setState(() {
      _documents = documents;
      _isLoading = false;
    });
  }

  Future<void> _openDocument(File file) async {
    if (_isBusy) return;

    final type = _documentType(file.path);

    if (type == 'pdf') {
      await _addRecentDocument(
        path: file.path,
        type: 'pdf',
        displayTitle: _displayTitleFromPath(file.path),
      );

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfTranslatorPage(initialPdfPath: file.path),
        ),
      );
      return;
    }

    if (type == 'epub') {
      setState(() {
        _isBusy = true;
      });

      try {
        final book = await EpubService().readEpub(file);

        if (!mounted) return;

        await _addRecentDocument(
          path: file.path,
          type: 'epub',
          displayTitle: _epubDisplayTitle(book, file.path),
          author: book.author,
          thumbnailPath: book.coverPath,
        );

        if (!mounted) return;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EpubReaderPage(book: book, documentPath: file.path),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Errore apertura EPUB: $e')));
      } finally {
        if (mounted) {
          setState(() {
            _isBusy = false;
          });
        }
      }
    }
  }

  Future<void> _deleteDocument(File file) async {
    final title = _displayTitleFromPath(file.path);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Elimina copia interna'),
          content: const Text(
            'Vuoi eliminare la copia interna di questo documento? Il file originale esterno non verrà toccato. Eventuali recenti, progresso e segnalibri collegati saranno rimossi dall’app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Elimina'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    setState(() {
      _isBusy = true;
    });

    try {
      await _removeReadingProgress(file);
      final didDelete = await _documentImportService.deleteImportedDocument(
        file.path,
      );

      if (!didDelete) {
        throw StateError('Path non eliminabile');
      }

      await _storageService.removeRecentDocument(file.path);
      await _storageService.removeBookmarksForDocument(file.path);
      await _loadDocuments();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$title rimosso dall’archivio')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Non sono riuscito a eliminare la copia interna.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _removeReadingProgress(File file) async {
    final type = _documentType(file.path);

    if (type == 'pdf') {
      final pdfStorageKey = await _storageService.makePdfStorageKey(file.path);
      await _storageService.removeSavedPage(pdfStorageKey);
      return;
    }

    if (type == 'epub') {
      try {
        final book = await EpubService().readEpub(file);
        final epubStorageKey = _storageService.makeEpubStorageKey(book.title);

        await _storageService.removeEpubReadingPosition(epubStorageKey);
      } catch (_) {
        final fallbackKey = _storageService.makeEpubStorageKey(
          _displayTitleFromPath(file.path),
        );

        await _storageService.removeEpubReadingPosition(fallbackKey);
      }
    }
  }

  Future<void> _addRecentDocument({
    required String path,
    required String type,
    String? thumbnailPath,
    String? displayTitle,
    String? author,
  }) async {
    await _storageService.addRecentDocument(
      RecentDocument(
        path: path,
        name: _documentNameFromPath(path),
        type: type,
        openedAt: DateTime.now(),
        thumbnailPath: thumbnailPath,
        displayTitle: displayTitle,
        author: author,
      ),
    );
  }

  String _documentNameFromPath(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  String _displayTitleFromPath(String path) {
    return TextCleanerService.cleanDocumentTitle(_documentNameFromPath(path));
  }

  String _epubDisplayTitle(EpubBookData book, String path) {
    return book.title == 'EPUB senza titolo'
        ? _displayTitleFromPath(path)
        : book.title;
  }

  String _documentType(String path) {
    return path.split('.').last.toLowerCase();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';

    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';

    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';

    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  String _formatModifiedAt(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();

    return '$day/$month/$year';
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 54,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Nessun documento importato',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'I PDF e gli EPUB aperti dall’app appariranno qui.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentTile(BuildContext context, File file) {
    final colorScheme = Theme.of(context).colorScheme;
    final type = _documentType(file.path);
    final isPdf = type == 'pdf';
    final modifiedAt = file.lastModifiedSync();

    return Card(
      elevation: 1.2,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPdf
              ? colorScheme.errorContainer
              : colorScheme.secondaryContainer,
          foregroundColor: isPdf
              ? colorScheme.onErrorContainer
              : colorScheme.onSecondaryContainer,
          child: Icon(isPdf ? Icons.picture_as_pdf : Icons.menu_book),
        ),
        title: Text(
          _displayTitleFromPath(file.path),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${type.toUpperCase()} · ${_formatBytes(file.lengthSync())} · ${_formatModifiedAt(modifiedAt)}',
        ),
        trailing: PopupMenuButton<String>(
          enabled: !_isBusy,
          onSelected: (value) {
            switch (value) {
              case 'open':
                _openDocument(file);
                break;
              case 'delete':
                _deleteDocument(file);
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'open',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.open_in_new),
                title: Text('Apri'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline),
                title: Text('Elimina copia interna'),
              ),
            ),
          ],
        ),
        onTap: _isBusy ? null : () => _openDocument(file),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Documenti importati')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDocuments,
              child: _documents.isEmpty
                  ? ListView(children: [_buildEmptyState(context)])
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.55,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Spazio usato: ${_formatBytes(_totalBytes)}',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final file in _documents)
                          _buildDocumentTile(context, file),
                      ],
                    ),
            ),
    );
  }
}
