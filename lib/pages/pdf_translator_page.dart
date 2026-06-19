import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/bookmark_item.dart';
import '../models/history_item.dart';
import '../models/recent_document.dart';
import '../services/ai_service.dart';
import '../services/export_service.dart';
import '../services/storage_service.dart';
import 'result_page.dart';
import '../services/text_cleaner_service.dart';
import '../widgets/translation_panel.dart';
import 'history_page.dart';
import 'home_page.dart';

import '../pages/epub_reader_page.dart';
import '../services/epub_service.dart';

class PdfTranslatorPage extends StatefulWidget {
  final String? initialPdfPath;
  final int? initialPageNumber;

  const PdfTranslatorPage({
    super.key,
    this.initialPdfPath,
    this.initialPageNumber,
  });

  @override
  State<PdfTranslatorPage> createState() => _PdfTranslatorPageState();
}

class _PdfTranslatorPageState extends State<PdfTranslatorPage> {
  final PdfViewerController pdfController = PdfViewerController();
  final AiService aiService = AiService();
  final StorageService storageService = StorageService();
  final ExportService exportService = ExportService();
  final ValueNotifier<_PdfProgressState> pdfProgressNotifier =
      ValueNotifier<_PdfProgressState>(const _PdfProgressState());

  File? pdfFile;
  String? pdfStorageKey;

  String selectedText = '';
  String resultText = '';
  String resultTitle = 'Risultato';
  String historySearch = '';

  bool isLoading = false;
  bool autoTranslate = false;

  int currentPage = 1;

  AiProvider selectedProvider = AiProvider.openai;

  List<HistoryItem> history = [];
  List<RecentDocument> recentDocuments = [];
  List<BookmarkItem> bookmarks = [];
  Map<String, String> cache = {};

  Timer? autoTranslateTimer;
  String lastAutoTranslateKey = '';
  int aiRequestVersion = 0;

  @override
  void initState() {
    super.initState();
    initializePage();
  }

  @override
  void dispose() {
    autoTranslateTimer?.cancel();
    pdfProgressNotifier.dispose();
    super.dispose();
  }

  Future<void> loadSettings() async {
    final provider = await storageService.loadProvider();
    final savedAutoTranslate = await storageService.loadAutoTranslate();

    if (!mounted) return;

    setState(() {
      selectedProvider = provider;
      autoTranslate = savedAutoTranslate;
    });
  }

  Future<void> loadHistory() async {
    final savedHistory = await storageService.loadHistory();

    if (!mounted) return;

    setState(() {
      history = savedHistory;
    });
  }

  Future<void> loadCache() async {
    final savedCache = await storageService.loadCache();

    if (!mounted) return;

    setState(() {
      cache = savedCache;
    });
  }

  Future<void> loadRecentDocuments() async {
    final savedRecentDocuments = await storageService.loadRecentDocuments();

    if (!mounted) return;

    setState(() {
      recentDocuments = savedRecentDocuments;
    });
  }

  Future<void> loadBookmarks() async {
    final savedBookmarks = await storageService.getBookmarks();

    if (!mounted) return;

    setState(() {
      bookmarks = savedBookmarks;
    });
  }

  Future<void> initializePage() async {
    await loadSettings();
    await loadHistory();
    await loadCache();
    await loadRecentDocuments();
    await loadBookmarks();

    if (!mounted || widget.initialPdfPath == null) return;

    await openPdfPath(
      widget.initialPdfPath!,
      initialPage: widget.initialPageNumber,
    );
  }

  Future<void> pickPdf() async {
    final result = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null || result.files.single.path == null) return;

    await openPdfPath(result.files.single.path!);
  }

  Future<void> pickEpub() async {
    final result = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['epub'],
    );

    if (result == null || result.files.single.path == null) return;

    await openEpubPath(result.files.single.path!);
  }

  Future<void> pickDocument() async {
    final result = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['pdf', 'epub'],
    );

    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final extension = path.split('.').last.toLowerCase();

    if (extension == 'pdf') {
      await openPdfPath(path);
    } else if (extension == 'epub') {
      await openEpubPath(path);
    }
  }

  Future<void> openPdfPath(String path, {int? initialPage}) async {
    await loadPdfFile(File(path), initialPage: initialPage);
  }

  Future<void> loadPdfFile(File file, {int? initialPage}) async {
    final path = file.path;
    final key = await storageService.makePdfStorageKey(path);
    final savedPage = await storageService.loadSavedPage(key);

    if (!mounted) return;

    setState(() {
      pdfStorageKey = key;
      pdfFile = file;
      selectedText = '';
      resultText = '';
      resultTitle = 'Risultato';
      currentPage = initialPage ?? savedPage;
      lastAutoTranslateKey = '';
    });
    _updatePdfProgressNotifier(totalPages: 0);

    await addRecentDocument(path: path, type: 'pdf');
  }

  Future<void> openEpubPath(String path) async {
    final file = File(path);

    try {
      final book = await EpubService().readEpub(file);

      if (!mounted) return;

      await addRecentDocument(
        path: path,
        type: 'epub',
        displayTitle: epubDisplayTitle(book, file.path),
        author: book.author,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
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
    }
  }

  String documentNameFromPath(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  String cleanDocumentTitleFromPath(String path) {
    return cleanDocumentTitle(documentNameFromPath(path));
  }

  String cleanDocumentTitle(String name) {
    final dotIndex = name.lastIndexOf('.');
    final title = dotIndex > 0 ? name.substring(0, dotIndex) : name;
    final cleaned = title
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned.isEmpty ? name : cleaned;
  }

  String epubDisplayTitle(EpubBookData book, String path) {
    return book.title == 'EPUB senza titolo'
        ? cleanDocumentTitleFromPath(path)
        : book.title;
  }

  Future<void> addRecentDocument({
    required String path,
    required String type,
    String? displayTitle,
    String? author,
  }) async {
    await storageService.addRecentDocument(
      RecentDocument(
        path: path,
        name: documentNameFromPath(path),
        type: type,
        openedAt: DateTime.now(),
        displayTitle: displayTitle ?? cleanDocumentTitleFromPath(path),
        author: author,
      ),
    );

    await loadRecentDocuments();
  }

  Future<void> openRecentDocument(RecentDocument document) async {
    if (!File(document.path).existsSync()) {
      await storageService.removeRecentDocument(document.path);
      await loadRecentDocuments();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File non trovato')));
      return;
    }

    if (document.type == 'pdf') {
      await openPdfPath(document.path);
    } else if (document.type == 'epub') {
      await openEpubPath(document.path);
    }
  }

  Future<void> saveCurrentPage() async {
    if (pdfStorageKey == null) return;

    await storageService.saveCurrentPage(
      pdfStorageKey: pdfStorageKey!,
      currentPage: currentPage,
    );
  }

  void _updatePdfProgressNotifier({int? totalPages}) {
    pdfProgressNotifier.value = _PdfProgressState(
      currentPage: currentPage,
      totalPages: totalPages ?? pdfProgressNotifier.value.totalPages,
    );
  }

  BookmarkItem? currentPdfBookmark() {
    final path = pdfFile?.path;
    if (path == null) return null;

    for (final bookmark in bookmarks) {
      if (bookmark.documentType == 'pdf' &&
          bookmark.documentPath == path &&
          bookmark.pageNumber == currentPage) {
        return bookmark;
      }
    }

    return null;
  }

  Future<void> toggleCurrentPdfBookmark() async {
    final file = pdfFile;
    if (file == null) return;

    final existingBookmark = currentPdfBookmark();

    if (existingBookmark != null) {
      await storageService.removeBookmark(existingBookmark.id);
      await loadBookmarks();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Segnalibro rimosso')));
      return;
    }

    await storageService.addBookmark(
      BookmarkItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        documentPath: file.path,
        documentName: documentNameFromPath(file.path),
        documentType: 'pdf',
        createdAt: DateTime.now(),
        pageNumber: currentPage,
        displayTitle: cleanDocumentTitleFromPath(file.path),
        positionLabel: 'Pagina $currentPage',
      ),
    );
    await loadBookmarks();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Segnalibro aggiunto')));
  }

  List<BookmarkItem> currentPdfBookmarks() {
    final path = pdfFile?.path;
    if (path == null) return [];

    final currentBookmarks = bookmarks
        .where(
          (bookmark) =>
              bookmark.documentType == 'pdf' &&
              bookmark.documentPath == path &&
              bookmark.pageNumber != null,
        )
        .toList();

    currentBookmarks.sort(
      (a, b) => (a.pageNumber ?? 0).compareTo(b.pageNumber ?? 0),
    );

    return currentBookmarks;
  }

  void showPdfBookmarks() {
    final currentBookmarks = currentPdfBookmarks();

    if (currentBookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessun segnalibro salvato per questo PDF.'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: currentBookmarks.length,
            itemBuilder: (context, index) {
              final bookmark = currentBookmarks[index];
              final pageNumber = bookmark.pageNumber ?? 1;

              return ListTile(
                leading: const Icon(Icons.bookmark_border),
                title: Text('Pagina $pageNumber'),
                onTap: () {
                  Navigator.pop(context);

                  setState(() {
                    currentPage = pageNumber;
                  });
                  _updatePdfProgressNotifier();

                  pdfController.jumpToPage(pageNumber);
                  saveCurrentPage();
                },
              );
            },
          ),
        );
      },
    );
  }

  String limitedSelectedText() {
    final text = TextCleanerService.normalizePdfText(selectedText);

    if (text.length <= 1200) return text;

    return text.substring(0, 1200);
  }

  Future<void> askAi(String action) async {
    final text = limitedSelectedText();
    if (text.isEmpty) return;

    final title = aiService.actionTitle(action);
    final provider = aiService.providerName(selectedProvider);

    final cacheKey = aiService.makeCacheKey(
      action: action,
      provider: provider,
      text: text,
    );

    if (cache.containsKey(cacheKey)) {
      setState(() {
        resultTitle = '$title Â· $provider Â· cache';
        resultText = cache[cacheKey]!;
      });

      return;
    }

    final prompt = aiService.buildPrompt(action, text);
    final requestVersion = aiRequestVersion;

    setState(() {
      isLoading = true;
      resultTitle = '$title Â· $provider';
      resultText = '';
    });

    try {
      final parsed = await aiService.callSelectedAi(
        provider: selectedProvider,
        prompt: prompt,
      );

      if (!mounted || requestVersion != aiRequestVersion) return;

      cache[cacheKey] = parsed;
      await storageService.saveCache(cache);

      if (!mounted || requestVersion != aiRequestVersion) return;

      final item = HistoryItem(
        pdfKey: pdfStorageKey ?? '',
        action: title,
        provider: provider,
        original: text,
        result: parsed,
        page: currentPage,
        date: DateTime.now(),
      );

      setState(() {
        resultText = parsed;
        history.insert(0, item);
      });

      await storageService.saveHistory(history);
    } catch (e) {
      if (!mounted || requestVersion != aiRequestVersion) return;

      setState(() {
        resultTitle = 'Errore';
        resultText = e.toString();
      });
    } finally {
      if (mounted && requestVersion == aiRequestVersion) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void scheduleAutoTranslate(String newText) {
    autoTranslateTimer?.cancel();

    if (!autoTranslate) return;
    if (newText.trim().isEmpty) return;
    if (isLoading) return;

    autoTranslateTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (!autoTranslate) return;

      final text = limitedSelectedText();
      if (text.isEmpty) return;

      final provider = aiService.providerName(selectedProvider);

      final key = aiService.makeCacheKey(
        action: 'traduci',
        provider: provider,
        text: text,
      );

      if (key == lastAutoTranslateKey) return;

      lastAutoTranslateKey = key;
      askAi('traduci');
    });
  }

  void showActionPopup() {
    if (selectedText.trim().isEmpty) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    askAi('traduci');
                  },
                  icon: const Icon(Icons.translate),
                  label: const Text('Traduci'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    askAi('spiega');
                  },
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Spiega'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    askAi('riassumi');
                  },
                  icon: const Icon(Icons.short_text),
                  label: const Text('Riassumi'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    askAi('vocabolario');
                  },
                  icon: const Icon(Icons.menu_book),
                  label: const Text('Vocabolario'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> showCreditInfo() async {
    setState(() {
      isLoading = true;
      resultTitle = 'Credito API';
      resultText = '';
    });

    try {
      final deepSeekBalance = await aiService.getDeepSeekBalance();

      setState(() {
        resultTitle = 'Credito API';
        resultText =
            'OpenAI:\n'
            'OpenAI non fornisce un endpoint pubblico semplice per leggere il credito residuo tramite API key.\n'
            'Controlla il saldo dalla dashboard OpenAI.\n\n'
            '$deepSeekBalance';
      });
    } catch (e) {
      setState(() {
        resultTitle = 'Errore credito';
        resultText = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> exportHistory(String type) async {
    final query = historySearch.trim().toLowerCase();

    final currentPdfHistory = history.where((item) {
      final belongsToCurrentPdf = item.pdfKey == pdfStorageKey;

      if (!belongsToCurrentPdf) return false;
      if (query.isEmpty) return true;

      final searchableText = [
        item.action,
        item.provider,
        item.original,
        item.result,
        item.page.toString(),
      ].join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList();

    if (currentPdfHistory.isEmpty) return;

    final file = await exportService.exportHistory(
      history: currentPdfHistory,
      type: type,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Esportato in: ${file.path}')));
  }

  void showHistory() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return HistoryPage(
          history: history,
          currentPdfKey: pdfStorageKey,
          onTapItem: (item) {
            Navigator.pop(context);

            setState(() {
              currentPage = item.page;
              resultTitle =
                  '${item.action} · ${item.provider} - pagina ${item.page}';
              resultText = item.result;
            });
            _updatePdfProgressNotifier();

            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                pdfController.jumpToPage(item.page);
                saveCurrentPage();
              }
            });
          },
          onDeleteItem: (item) async {
            setState(() {
              history.remove(item);
            });

            await storageService.saveHistory(history);

            if (!mounted) return;

            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Voce eliminata')));
          },
          onClearPdfHistory: () async {
            setState(() {
              history.removeWhere((item) => item.pdfKey == pdfStorageKey);
            });

            await storageService.saveHistory(history);

            if (mounted) Navigator.pop(context);
          },
          onExportHistory: (type, filteredHistory) async {
            if (filteredHistory.isEmpty) return;

            final file = await exportService.exportHistory(
              history: filteredHistory,
              type: type,
            );

            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Esportato in: ${file.path}')),
            );
          },
        );
      },
    );
  }

  Future<void> clearCache() async {
    autoTranslateTimer?.cancel();
    aiRequestVersion++;

    setState(() {
      cache.clear();
      resultText = '';
      resultTitle = 'Risultato';
      lastAutoTranslateKey = '';
      isLoading = false;
    });

    await storageService.saveCache(cache);

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cache svuotata')));
  }

  void clearAll() {
    setState(() {
      selectedText = '';
      resultText = '';
      resultTitle = 'Risultato';
      lastAutoTranslateKey = '';
    });
  }

  void returnToHome() {
    autoTranslateTimer?.cancel();

    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }

    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  void openResult() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultPage(title: resultTitle, text: resultText),
      ),
    );
  }

  Widget buildNoPdfState() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: pickDocument,
        icon: const Icon(Icons.folder_open),
        label: const Text('Apri PDF o EPUB'),
      ),
    );
  }

  Widget buildPdfViewer() {
    if (pdfFile == null) {
      return buildNoPdfState();
    }

    return SfPdfViewer.file(
      pdfFile!,
      controller: pdfController,
      enableTextSelection: true,
      onDocumentLoaded: (details) {
        final totalPages = details.document.pages.count;
        if (totalPages > 0) {
          currentPage = currentPage.clamp(1, totalPages).toInt();
        }
        _updatePdfProgressNotifier(totalPages: totalPages);

        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && currentPage > 1) {
            pdfController.jumpToPage(currentPage);
          }
        });
      },
      onPageChanged: (details) {
        currentPage = details.newPageNumber;
        _updatePdfProgressNotifier();
        saveCurrentPage();
      },
      onTextSelectionChanged: (details) {
        final newText = details.selectedText ?? '';

        setState(() {
          selectedText = newText;
        });

        scheduleAutoTranslate(newText);
      },
    );
  }

  Widget buildPdfProgressBar() {
    if (pdfFile == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<_PdfProgressState>(
      valueListenable: pdfProgressNotifier,
      builder: (context, progressState, _) {
        return ColoredBox(
          color: colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  progressState.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: progressState.progress,
                    backgroundColor: colorScheme.onSurface.withValues(
                      alpha: 0.10,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildPdfBody() {
    return Column(
      children: [
        buildPdfProgressBar(),
        Expanded(child: buildPdfViewer()),
        ValueListenableBuilder<_PdfProgressState>(
          valueListenable: pdfProgressNotifier,
          builder: (context, progressState, _) {
            return TranslationPanel(
              selectedText: selectedText,
              resultText: resultText,
              resultTitle: resultTitle,
              isLoading: isLoading,
              currentPage: progressState.currentPage,
              autoTranslate: autoTranslate,
              selectedProvider: selectedProvider,
              onProviderChanged: (value) {
                setState(() {
                  selectedProvider = value;
                  lastAutoTranslateKey = '';
                });

                storageService.saveProvider(value);
              },
              onAutoTranslateChanged: (value) {
                setState(() {
                  autoTranslate = value;
                  lastAutoTranslateKey = '';
                });

                storageService.saveAutoTranslate(value);

                if (value && selectedText.trim().isNotEmpty) {
                  scheduleAutoTranslate(selectedText);
                }
              },
              onShowActionPopup: showActionPopup,
              onAskAi: askAi,
              onOpenResult: openResult,
            );
          },
        ),
      ],
    );
  }

  PreferredSizeWidget buildPdfAppBar() {
    return AppBar(
      actions: [
        ValueListenableBuilder<_PdfProgressState>(
          valueListenable: pdfProgressNotifier,
          builder: (context, _, _) {
            final isBookmarked = currentPdfBookmark() != null;

            return IconButton(
              tooltip: isBookmarked
                  ? 'Rimuovi segnalibro'
                  : 'Aggiungi segnalibro',
              icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border),
              onPressed: pdfFile == null ? null : toggleCurrentPdfBookmark,
            );
          },
        ),
        IconButton(
          tooltip: 'Segnalibri PDF',
          icon: const Icon(Icons.bookmarks_outlined),
          onPressed: pdfFile == null ? null : showPdfBookmarks,
        ),
        IconButton(
          tooltip: 'Credito',
          icon: const Icon(Icons.account_balance_wallet),
          onPressed: showCreditInfo,
        ),
        IconButton(
          tooltip: 'Cronologia PDF',
          icon: const Icon(Icons.history),
          onPressed: showHistory,
        ),
        IconButton(
          tooltip: 'Svuota cache',
          icon: const Icon(Icons.cached),
          onPressed: clearCache,
        ),
        IconButton(
          tooltip: 'Apri PDF o EPUB',
          icon: const Icon(Icons.folder_open),
          onPressed: pickDocument,
        ),
        IconButton(
          tooltip: 'Pulisci',
          icon: const Icon(Icons.clear),
          onPressed: clearAll,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: buildPdfAppBar(), body: buildPdfBody());
  }
}

class _PdfProgressState {
  final int currentPage;
  final int totalPages;

  const _PdfProgressState({this.currentPage = 1, this.totalPages = 0});

  double? get progress {
    if (totalPages <= 0) return null;

    return (currentPage / totalPages).clamp(0.0, 1.0).toDouble();
  }

  String get label {
    if (totalPages <= 0) return 'Pagina $currentPage';

    final safeProgress = progress ?? 0;
    final percent = (safeProgress * 100).round().clamp(0, 100);

    return 'Pagina $currentPage di $totalPages · $percent%';
  }
}
