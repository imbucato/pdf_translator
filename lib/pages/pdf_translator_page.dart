import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/history_item.dart';
import '../services/ai_service.dart';
import '../services/export_service.dart';
import '../services/storage_service.dart';
import 'result_page.dart';
import '../services/text_cleaner_service.dart';
import '../widgets/translation_panel.dart';
import 'history_page.dart';

import '../pages/epub_reader_page.dart';
import '../services/epub_service.dart';

class PdfTranslatorPage extends StatefulWidget {
  final String? initialPdfPath;

  const PdfTranslatorPage({super.key, this.initialPdfPath});

  @override
  State<PdfTranslatorPage> createState() => _PdfTranslatorPageState();
}

class _PdfTranslatorPageState extends State<PdfTranslatorPage> {
  final PdfViewerController pdfController = PdfViewerController();
  final AiService aiService = AiService();
  final StorageService storageService = StorageService();
  final ExportService exportService = ExportService();

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
  Map<String, String> cache = {};

  Timer? autoTranslateTimer;
  String lastAutoTranslateKey = '';

  @override
  void initState() {
    super.initState();
    initializePage();
  }

  @override
  void dispose() {
    autoTranslateTimer?.cancel();
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

  Future<void> initializePage() async {
    await loadSettings();
    await loadHistory();
    await loadCache();

    if (!mounted || widget.initialPdfPath == null) return;

    await openPdfPath(widget.initialPdfPath!);
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

  Future<void> openPdfPath(String path) async {
    await loadPdfFile(File(path));
  }

  Future<void> loadPdfFile(File file) async {
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
      currentPage = savedPage;
      lastAutoTranslateKey = '';
    });
  }

  Future<void> openEpubPath(String path) async {
    final file = File(path);

    try {
      final book = await EpubService().readEpub(file);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EpubReaderPage(book: book)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore apertura EPUB: $e')));
    }
  }

  Future<void> saveCurrentPage() async {
    if (pdfStorageKey == null) return;

    await storageService.saveCurrentPage(
      pdfStorageKey: pdfStorageKey!,
      currentPage: currentPage,
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

      cache[cacheKey] = parsed;
      await storageService.saveCache(cache);

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
      setState(() {
        resultTitle = 'Errore';
        resultText = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
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
    setState(() {
      cache.clear();
    });

    await storageService.clearCache();

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

  void resetToHome() {
    autoTranslateTimer?.cancel();

    setState(() {
      pdfFile = null;
      pdfStorageKey = null;
      selectedText = '';
      resultText = '';
      resultTitle = 'Risultato';
      currentPage = 1;
      isLoading = false;
      lastAutoTranslateKey = '';
    });
  }

  void openResult() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultPage(title: resultTitle, text: resultText),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPdf = pdfFile != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Translator'),
        actions: [
          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: resetToHome,
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
      ),
      body: Column(
        children: [
          Expanded(
            child: !hasPdf
                ? Center(
                    child: ElevatedButton.icon(
                      onPressed: pickDocument,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Apri PDF o EPUB'),
                    ),
                  )
                : SfPdfViewer.file(
                    pdfFile!,
                    controller: pdfController,
                    enableTextSelection: true,
                    onDocumentLoaded: (_) {
                      Future.delayed(const Duration(milliseconds: 400), () {
                        if (mounted && currentPage > 1) {
                          pdfController.jumpToPage(currentPage);
                        }
                      });
                    },
                    onPageChanged: (details) {
                      currentPage = details.newPageNumber;
                      saveCurrentPage();
                    },
                    onTextSelectionChanged: (details) {
                      final newText = details.selectedText ?? '';

                      setState(() {
                        selectedText = newText;
                      });

                      scheduleAutoTranslate(newText);
                    },
                  ),
          ),
          TranslationPanel(
            selectedText: selectedText,
            resultText: resultText,
            resultTitle: resultTitle,
            isLoading: isLoading,
            currentPage: currentPage,
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
          ),
        ],
      ),
    );
  }
}
