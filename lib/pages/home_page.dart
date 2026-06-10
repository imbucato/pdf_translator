import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import '../models/recent_document.dart';
import '../services/epub_service.dart';
import '../services/storage_service.dart';
import 'epub_reader_page.dart';
import 'pdf_translator_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final StorageService _storageService = StorageService();

  List<RecentDocument> _recentDocuments = [];
  bool _isOpeningDocument = false;

  @override
  void initState() {
    super.initState();
    _loadRecentDocuments();
  }

  Future<void> _loadRecentDocuments() async {
    final documents = await _storageService.loadRecentDocuments();

    if (!mounted) return;

    setState(() {
      _recentDocuments = documents;
    });
  }

  Future<void> _pickDocument() async {
    final result = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['pdf', 'epub'],
    );

    if (result == null || result.files.single.path == null) return;

    await _openDocumentPath(result.files.single.path!);
  }

  Future<void> _openRecentDocument(RecentDocument document) async {
    await _openDocumentPath(document.path);
  }

  Future<void> _openDocumentPath(String path) async {
    final file = File(path);

    if (!file.existsSync()) {
      await _storageService.removeRecentDocument(path);
      await _loadRecentDocuments();
      _showFileNotFound();
      return;
    }

    final extension = path.split('.').last.toLowerCase();

    if (extension == 'pdf') {
      await _openPdf(file);
    } else if (extension == 'epub') {
      await _openEpub(file);
    }
  }

  Future<void> _openPdf(File file) async {
    await _addRecentDocument(path: file.path, type: 'pdf');

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfTranslatorPage(initialPdfPath: file.path),
      ),
    );

    if (!mounted) return;

    await _loadRecentDocuments();
  }

  Future<void> _openEpub(File file) async {
    setState(() {
      _isOpeningDocument = true;
    });

    try {
      final book = await EpubService().readEpub(file);

      if (!mounted) return;

      await _addRecentDocument(path: file.path, type: 'epub');

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EpubReaderPage(book: book)),
      );

      if (!mounted) return;

      await _loadRecentDocuments();
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

  Future<void> _addRecentDocument({
    required String path,
    required String type,
  }) async {
    await _storageService.addRecentDocument(
      RecentDocument(
        path: path,
        name: _documentNameFromPath(path),
        type: type,
        openedAt: DateTime.now(),
      ),
    );
  }

  String _documentNameFromPath(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  void _showFileNotFound() {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('File non trovato')));
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.auto_stories_outlined, size: 40, color: colorScheme.primary),
        const SizedBox(height: 18),
        Text(
          'PDF Translator',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Leggi, traduci e analizza PDF ed EPUB',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildOpenDocumentAction(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isOpeningDocument ? null : _pickDocument,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: _isOpeningDocument
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Icon(Icons.folder_open, color: colorScheme.onPrimary),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apri documento',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PDF o EPUB',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentDocumentsSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget content;

    if (_recentDocuments.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(Icons.history, size: 34, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              'Nessun documento recente',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    } else {
      content = Column(
        children: _recentDocuments.map((document) {
          final isPdf = document.type.toLowerCase() == 'pdf';
          final typeLabel = isPdf ? 'PDF' : 'EPUB';

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(
              isPdf ? Icons.picture_as_pdf : Icons.menu_book,
              color: isPdf ? colorScheme.error : colorScheme.primary,
            ),
            title: Text(
              document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '$typeLabel - ${document.path}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: _isOpeningDocument
                ? null
                : () => _openRecentDocument(document),
          );
        }).toList(),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ultimi documenti',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            content,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Translator')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 28),
                  _buildOpenDocumentAction(context),
                  const SizedBox(height: 24),
                  _buildRecentDocumentsSection(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
