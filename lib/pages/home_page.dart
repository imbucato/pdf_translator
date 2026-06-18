import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import '../models/recent_document.dart';
import '../services/epub_service.dart';
import '../services/storage_service.dart';
import '../widgets/document_thumbnail.dart';
import 'bookmarks_page.dart';
import 'epub_reader_page.dart';
import 'pdf_translator_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final StorageService _storageService = StorageService();

  List<RecentDocument> _recentDocuments = [];
  Map<String, String> _recentPositionLabels = {};
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

    await _loadRecentPositionLabels(documents);
    await _backfillRecentDocumentData(documents);
  }

  Future<void> _loadRecentPositionLabels(List<RecentDocument> documents) async {
    final labels = <String, String>{};

    for (final document in documents) {
      labels[document.path] = await _recentPositionLabel(document);
    }

    if (!mounted) return;

    setState(() {
      _recentPositionLabels = labels;
    });
  }

  Future<void> _backfillRecentDocumentData(
    List<RecentDocument> documents,
  ) async {
    var didUpdate = false;
    final updatedDocuments = <RecentDocument>[];
    final epubService = EpubService();

    for (final document in documents) {
      final type = document.type.toLowerCase();
      final hasThumbnail = _thumbnailPathExists(document.thumbnailPath);
      final hasDisplayTitle = document.displayTitle?.trim().isNotEmpty == true;

      if (type != 'epub') {
        final displayTitle = _cleanDocumentTitle(
          document.displayTitle ?? document.name,
        );
        final updatedDocument = document.copyWith(displayTitle: displayTitle);

        updatedDocuments.add(document);
        if (updatedDocument.displayTitle != document.displayTitle) {
          updatedDocuments[updatedDocuments.length - 1] = updatedDocument;
          didUpdate = true;
        }
        continue;
      }

      final file = File(document.path);
      var thumbnailPath = document.thumbnailPath;
      var displayTitle = document.displayTitle;
      var author = document.author;

      if (!hasThumbnail || !hasDisplayTitle) {
        try {
          final book = await epubService.readEpub(file);

          thumbnailPath ??= book.coverPath;
          displayTitle ??= _epubDisplayTitle(book, file.path);
          author ??= book.author;
        } catch (_) {
          thumbnailPath ??= await epubService.cacheCoverForFile(file);
          displayTitle ??= _cleanDocumentTitle(document.name);
        }
      }

      final updatedDocument = document.copyWith(
        thumbnailPath: thumbnailPath,
        displayTitle: displayTitle,
        author: author,
      );

      updatedDocuments.add(updatedDocument);
      didUpdate =
          didUpdate ||
          updatedDocument.thumbnailPath != document.thumbnailPath ||
          updatedDocument.displayTitle != document.displayTitle ||
          updatedDocument.author != document.author;
    }

    if (!didUpdate) return;

    await _storageService.saveRecentDocuments(updatedDocuments);

    if (!mounted) return;

    setState(() {
      _recentDocuments = updatedDocuments;
    });
  }

  bool _thumbnailPathExists(String? path) {
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  Future<String> _recentPositionLabel(RecentDocument document) async {
    final type = document.type.toLowerCase();

    if (type == 'pdf') {
      return _pdfPositionLabel(document);
    }

    if (type == 'epub') {
      return _epubPositionLabel(document);
    }

    return document.type.toUpperCase();
  }

  Future<String> _pdfPositionLabel(RecentDocument document) async {
    const fallbackLabel = 'PDF';
    final file = File(document.path);

    if (!file.existsSync()) return fallbackLabel;

    try {
      final key = await _storageService.makePdfStorageKey(document.path);
      final page = await _storageService.loadSavedPageOrNull(key);

      if (page == null) return fallbackLabel;

      return 'PDF · Pagina $page';
    } catch (_) {
      return fallbackLabel;
    }
  }

  Future<String> _epubPositionLabel(RecentDocument document) async {
    const fallbackLabel = 'EPUB';
    final file = File(document.path);

    if (!file.existsSync()) return fallbackLabel;

    try {
      final book = await EpubService().readEpub(file);
      final key = _storageService.makeEpubStorageKey(book.title);
      final progress = await _storageService.loadEpubProgress(key);

      if (progress != null) return 'EPUB · $progress%';

      final offset = await _storageService.loadSavedEpubScrollOffsetOrNull(key);

      if (offset == null || offset <= 0) return fallbackLabel;

      return 'EPUB · Posizione salvata';
    } catch (_) {
      return fallbackLabel;
    }
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

  Future<void> _removeRecentDocument(RecentDocument document) async {
    await _storageService.removeRecentDocument(document.path);
    await _loadRecentDocuments();
  }

  Future<void> _togglePinnedRecentDocument(RecentDocument document) async {
    await _storageService.updateRecentDocumentPinned(
      document.path,
      !document.isPinned,
    );
    await _loadRecentDocuments();
  }

  Future<void> _clearRecentDocuments() async {
    await _storageService.clearRecentDocuments();
    await _loadRecentDocuments();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Elenco recenti svuotato')));
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
    await _addRecentDocument(
      path: file.path,
      type: 'pdf',
      displayTitle: _cleanDocumentTitleFromPath(file.path),
    );

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

      await _addRecentDocument(
        path: file.path,
        type: 'epub',
        thumbnailPath: book.coverPath,
        displayTitle: _epubDisplayTitle(book, file.path),
        author: book.author,
      );

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EpubReaderPage(book: book, documentPath: file.path),
        ),
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

  String _cleanDocumentTitleFromPath(String path) {
    return _cleanDocumentTitle(_documentNameFromPath(path));
  }

  String _cleanDocumentTitle(String name) {
    final dotIndex = name.lastIndexOf('.');
    final title = dotIndex > 0 ? name.substring(0, dotIndex) : name;
    final cleaned = title
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned.isEmpty ? name : cleaned;
  }

  String _epubDisplayTitle(EpubBookData book, String path) {
    return book.title == 'EPUB senza titolo'
        ? _cleanDocumentTitleFromPath(path)
        : book.title;
  }

  void _showFileNotFound() {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('File non trovato')));
  }

  void _showAboutDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    final features = [
      'Lettura PDF',
      'Lettura EPUB',
      'Traduzione',
      'Spiegazione',
      'Riassunto',
      'Vocabolario',
      'Storico e documenti recenti',
    ];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          icon: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.auto_stories,
              color: colorScheme.onPrimaryContainer,
              size: 38,
            ),
          ),
          title: Text(
            'AI Reader',
            textAlign: TextAlign.center,
            style: Theme.of(
              dialogContext,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Leggi, traduci e approfondisci PDF ed EPUB',
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: features
                    .map(
                      (feature) => Chip(
                        avatar: const Icon(Icons.check_circle, size: 18),
                        label: Text(feature),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  String _formatOpenedAt(DateTime openedAt) {
    if (openedAt.millisecondsSinceEpoch == 0) return '';

    final day = openedAt.day.toString().padLeft(2, '0');
    final month = openedAt.month.toString().padLeft(2, '0');
    final year = openedAt.year.toString();
    final hour = openedAt.hour.toString().padLeft(2, '0');
    final minute = openedAt.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 3,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.auto_stories,
                    color: colorScheme.onPrimaryContainer,
                    size: 36,
                  ),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: 'Impostazioni',
                  icon: const Icon(Icons.settings),
                  onPressed: _openSettings,
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Info app',
                  icon: const Icon(Icons.info_outline),
                  onPressed: _showAboutDialog,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'AI Reader',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Leggi, traduci e approfondisci PDF ed EPUB',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenDocumentAction(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 4,
      shadowColor: colorScheme.primary.withValues(alpha: 0.26),
      margin: EdgeInsets.zero,
      color: colorScheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isOpeningDocument ? null : _pickDocument,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: _isOpeningDocument
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Icon(
                          Icons.folder_open,
                          color: colorScheme.onPrimary,
                          size: 30,
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apri documento',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PDF o EPUB',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimary.withValues(alpha: 0.86),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onPrimary,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarksAction(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1.5,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.10),
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.bookmarks, color: colorScheme.onSecondaryContainer),
        ),
        title: Text(
          'Segnalibri',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'Pagine e capitoli salvati',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _isOpeningDocument
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BookmarksPage()),
                );
              },
      ),
    );
  }

  Widget _buildEmptyRecentDocuments(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.history,
                size: 30,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Nessun documento recente',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Apri un PDF o un EPUB per iniziare',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentDocumentCard(
    BuildContext context,
    RecentDocument document,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final type = document.type.toLowerCase();
    final isPdf = type == 'pdf';
    final typeLabel = isPdf ? 'PDF' : 'EPUB';
    final positionLabel = _recentPositionLabels[document.path] ?? typeLabel;
    final openedAt = _formatOpenedAt(document.openedAt);
    final displayTitle = document.type.toLowerCase() == 'pdf'
        ? _cleanDocumentTitle(document.displayTitle ?? document.name)
        : document.displayTitle ?? _cleanDocumentTitle(document.name);
    final author = document.author;

    return Card(
      elevation: 1.5,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.10),
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        minLeadingWidth: 44,
        leading: DocumentThumbnail(
          documentType: document.type,
          thumbnailPath: document.thumbnailPath,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (document.isPinned) ...[
              const SizedBox(width: 6),
              Icon(Icons.push_pin, size: 16, color: colorScheme.primary),
            ],
          ],
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
                const SizedBox(height: 5),
              ],
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      positionLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (openedAt.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        openedAt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Azioni documento',
          enabled: !_isOpeningDocument,
          onSelected: (value) {
            switch (value) {
              case 'pin':
                _togglePinnedRecentDocument(document);
                break;
              case 'remove':
                _removeRecentDocument(document);
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'pin',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  document.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                ),
                title: Text(
                  document.isPinned ? 'Rimuovi fissaggio' : 'Fissa in alto',
                ),
              ),
            ),
            const PopupMenuItem(
              value: 'remove',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.close),
                title: Text('Rimuovi dai recenti'),
              ),
            ),
          ],
        ),
        onTap: _isOpeningDocument ? null : () => _openRecentDocument(document),
      ),
    );
  }

  Widget _buildRecentDocumentsHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Ultimi documenti',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Svuota recenti',
          icon: const Icon(Icons.clear_all),
          onPressed: _recentDocuments.isEmpty || _isOpeningDocument
              ? null
              : _clearRecentDocuments,
        ),
      ],
    );
  }

  Widget _buildRecentDocumentsList(BuildContext context) {
    if (_recentDocuments.isEmpty) {
      return _buildEmptyRecentDocuments(context);
    }

    return Column(
      children: _recentDocuments
          .map((document) => _buildRecentDocumentCard(context, document))
          .toList(),
    );
  }

  Widget _buildRecentDocumentsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRecentDocumentsHeader(context),
        const SizedBox(height: 12),
        _buildRecentDocumentsList(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.045),
        colorScheme.surface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 18),
                  _buildOpenDocumentAction(context),
                  const SizedBox(height: 12),
                  _buildBookmarksAction(context),
                  const SizedBox(height: 28),
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
