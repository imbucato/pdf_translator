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
import 'history_page.dart';

class PdfTranslatorPage extends StatefulWidget {
  const PdfTranslatorPage({super.key});

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
    loadSettings();
    loadHistory();
    loadCache();
  }

  @override
  void dispose() {
    autoTranslateTimer?.cancel();
    super.dispose();
  }

  Future<void> loadSettings() async {
    final provider = await storageService.loadProvider();
    final savedAutoTranslate = await storageService.loadAutoTranslate();

    setState(() {
      selectedProvider = provider;
      autoTranslate = savedAutoTranslate;
    });
  }

  Future<void> loadHistory() async {
    final savedHistory = await storageService.loadHistory();

    setState(() {
      history = savedHistory;
    });
  }

  Future<void> loadCache() async {
    final savedCache = await storageService.loadCache();

    setState(() {
      cache = savedCache;
    });
  }

  Future<void> pickPdf() async {
    final result = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final key = await storageService.makePdfStorageKey(path);
    final savedPage = await storageService.loadSavedPage(key);

    setState(() {
      pdfStorageKey = key;
      pdfFile = File(path);
      selectedText = '';
      resultText = '';
      resultTitle = 'Risultato';
      currentPage = savedPage;
      lastAutoTranslateKey = '';
    });
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

  @override
  Widget build(BuildContext context) {
    final hasPdf = pdfFile != null;
    final hasSelection = selectedText.trim().isNotEmpty;
    final isLimited = selectedText.trim().length > 1200;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Translator'),
        actions: [
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
            tooltip: 'Apri PDF',
            icon: const Icon(Icons.folder_open),
            onPressed: pickPdf,
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
                      onPressed: pickPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Apri PDF'),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'AI: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      DropdownButton<AiProvider>(
                        value: selectedProvider,
                        items: const [
                          DropdownMenuItem(
                            value: AiProvider.openai,
                            child: Text('OpenAI'),
                          ),
                          DropdownMenuItem(
                            value: AiProvider.deepseek,
                            child: Text('DeepSeek'),
                          ),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) {
                                if (value == null) return;

                                setState(() {
                                  selectedProvider = value;
                                  lastAutoTranslateKey = '';
                                });

                                storageService.saveProvider(value);
                              },
                      ),
                      const Spacer(),
                      const Text('Auto'),
                      Switch(
                        value: autoTranslate,
                        onChanged: (value) {
                          setState(() {
                            autoTranslate = value;
                            lastAutoTranslateKey = '';
                          });

                          storageService.saveAutoTranslate(value);

                          if (value && selectedText.trim().isNotEmpty) {
                            scheduleAutoTranslate(selectedText);
                          }
                        },
                      ),
                    ],
                  ),
                  Text(
                    hasSelection
                        ? 'Testo selezionato: ${selectedText.length} caratteri - pagina $currentPage'
                        : 'Pagina $currentPage - seleziona una frase nel PDF',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (isLimited)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Verranno inviati solo i primi 1200 caratteri.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (hasSelection) ...[
                    const SizedBox(height: 6),
                    Text(
                      selectedText.length > 180
                          ? '${selectedText.substring(0, 180)}...'
                          : selectedText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: isLoading ? null : showActionPopup,
                          icon: const Icon(Icons.touch_app),
                          label: const Text('Azioni'),
                        ),
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : () => askAi('traduci'),
                          icon: const Icon(Icons.translate),
                          label: const Text('Traduci'),
                        ),
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : () => askAi('spiega'),
                          icon: const Icon(Icons.lightbulb_outline),
                          label: const Text('Spiega'),
                        ),
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : () => askAi('riassumi'),
                          icon: const Icon(Icons.short_text),
                          label: const Text('Riassumi'),
                        ),
                        OutlinedButton.icon(
                          onPressed: isLoading
                              ? null
                              : () => askAi('vocabolario'),
                          icon: const Icon(Icons.menu_book),
                          label: const Text('Vocabolario'),
                        ),
                      ],
                    ),
                  ],
                  if (isLoading) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (resultText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      resultTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const SizedBox(height: 8),

                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_full),
                        label: const Text('Apri risultato'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ResultPage(
                                title: resultTitle,
                                text: resultText,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          resultText,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
