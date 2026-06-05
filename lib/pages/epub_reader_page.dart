import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import '../models/history_item.dart';
import '../services/ai_service.dart';
import '../services/epub_service.dart';
import '../services/storage_service.dart';
import '../services/text_cleaner_service.dart';
import '../widgets/translation_panel.dart';
import 'history_page.dart';
import 'pdf_translator_page.dart';
import 'result_page.dart';

class EpubReaderPage extends StatefulWidget {
  final EpubBookData book;

  const EpubReaderPage({super.key, required this.book});

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  final ScrollController _scrollController = ScrollController();
  final AiService _aiService = AiService();
  final StorageService _storageService = StorageService();

  late final List<GlobalKey> _chapterKeys;
  late final String _epubStorageKey;

  Timer? _savePositionDebounce;
  Timer? _autoTranslateTimer;
  int _selectionClearVersion = 0;
  int selectedChapterIndex = 0;
  String selectedText = '';
  String resultTitle = 'Risultato';
  String resultText = '';
  String lastAutoTranslateKey = '';
  double? selectedTextScrollOffset;

  bool isLoading = false;
  bool autoTranslate = false;

  AiProvider selectedProvider = AiProvider.openai;
  Map<String, String> cache = {};
  List<HistoryItem> history = [];
  int _aiRequestVersion = 0;

  @override
  void initState() {
    super.initState();

    _chapterKeys = List.generate(
      widget.book.chapters.length,
      (_) => GlobalKey(),
    );
    _epubStorageKey = _storageService.makeEpubStorageKey(widget.book.title);

    _scrollController.addListener(_saveReadingPositionSoon);
    _restoreReadingPosition();
    _loadSettings();
    _loadCache();
    _loadHistory();
  }

  Future<void> _loadSettings() async {
    final provider = await _storageService.loadProvider();
    final savedAutoTranslate = await _storageService.loadAutoTranslate();

    if (!mounted) return;

    setState(() {
      selectedProvider = provider;
      autoTranslate = savedAutoTranslate;
    });
  }

  Future<void> _loadCache() async {
    final savedCache = await _storageService.loadCache();

    if (!mounted) return;

    setState(() {
      cache = savedCache;
    });
  }

  Future<void> _loadHistory() async {
    final savedHistory = await _storageService.loadHistory();

    if (!mounted) return;

    setState(() {
      history = savedHistory;
    });
  }

  Future<void> openResultPage() async {
    if (resultText.trim().isEmpty) return;

    final savedOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultPage(title: resultTitle, text: resultText),
      ),
    );

    if (!mounted || savedOffset == null) return;

    Future<void> restoreOffset() async {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;

      final restoredOffset = savedOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      _scrollController.jumpTo(restoredOffset);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      restoreOffset();
    });

    await Future.delayed(const Duration(milliseconds: 80));
    await restoreOffset();
  }

  Future<void> showCreditInfo() async {
    setState(() {
      isLoading = true;
      resultTitle = 'Credito API';
      resultText = '';
    });

    try {
      final deepSeekBalance = await _aiService.getDeepSeekBalance();

      if (!mounted) return;

      setState(() {
        resultTitle = 'Credito API';
        resultText =
            'OpenAI:\n'
            'OpenAI non fornisce un endpoint pubblico semplice per leggere il credito residuo tramite API key.\n'
            'Controlla il saldo dalla dashboard OpenAI.\n\n'
            '$deepSeekBalance';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        resultTitle = 'Errore credito';
        resultText = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> clearCache() async {
    _autoTranslateTimer?.cancel();
    _aiRequestVersion++;

    setState(() {
      cache.clear();
      resultText = '';
      resultTitle = 'Risultato';
      lastAutoTranslateKey = '';
      isLoading = false;
    });

    await _storageService.saveCache(cache);

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cache svuotata')));
  }

  Future<void> showEpubHistory() async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return HistoryPage(
          history: history,
          currentPdfKey: _epubStorageKey,
          clearHistoryLabel: 'Svuota EPUB',
          emptyHistoryLabel: 'Nessuna cronologia per questo EPUB',
          locationLabel: 'capitolo',
          onTapItem: _openHistoryItem,
          onDeleteItem: (item) async {
            setState(() {
              history.remove(item);
            });

            await _storageService.saveHistory(history);

            if (!mounted) return;

            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Voce eliminata')));
          },
          onClearPdfHistory: () async {
            setState(() {
              history.removeWhere((item) => item.pdfKey == _epubStorageKey);
            });

            await _storageService.saveHistory(history);

            if (mounted) Navigator.pop(context);
          },
          onExportHistory: (type, filteredHistory) async {
            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Export EPUB non disponibile per ora.'),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> pickDocument() async {
    final result = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['pdf', 'epub'],
    );

    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final extension = path.split('.').last.toLowerCase();

    if (extension == 'epub') {
      await _openEpubPath(path);
    } else if (extension == 'pdf') {
      if (!mounted) return;

      final file = File(path);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PdfTranslatorPage(initialPdfPath: file.path),
        ),
      );
    }
  }

  Future<void> _openEpubPath(String path) async {
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

  void showChapterSelector() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: ListView.builder(
            itemCount: widget.book.chapters.length,
            itemBuilder: (context, index) {
              final chapter = widget.book.chapters[index];

              return ListTile(
                title: Text(chapter.title),
                selected: index == selectedChapterIndex,
                onTap: () {
                  Navigator.pop(context);
                  _scrollToChapter(index);
                },
              );
            },
          ),
        );
      },
    );
  }

  String _limitedSelectedText() {
    final text = TextCleanerService.normalizePdfText(selectedText);

    if (text.length <= 1200) return text;

    return text.substring(0, 1200);
  }

  Future<void> _saveHistoryItem({
    required String action,
    required String provider,
    required String original,
    required String result,
  }) async {
    final chapterIndex = _currentVisibleChapterIndex();
    final currentOffset =
        selectedTextScrollOffset ??
        (_scrollController.hasClients ? _scrollController.offset : null);

    final item = HistoryItem(
      pdfKey: _epubStorageKey,
      action: action,
      provider: provider,
      original: original,
      result: result,
      page: chapterIndex + 1,
      date: DateTime.now(),
      scrollOffset: currentOffset,
    );

    setState(() {
      selectedChapterIndex = chapterIndex;
      history.insert(0, item);
    });

    await _storageService.saveHistory(history);
  }

  Future<void> _askAi(String action) async {
    final text = _limitedSelectedText();
    if (text.isEmpty) return;

    final title = _aiService.actionTitle(action);
    final provider = _aiService.providerName(selectedProvider);

    final cacheKey = _aiService.makeCacheKey(
      action: action,
      provider: provider,
      text: text,
    );

    if (cache.containsKey(cacheKey)) {
      final cachedResult = cache[cacheKey]!;

      setState(() {
        resultTitle = '$title - $provider - cache';
        resultText = cachedResult;
      });

      await _saveHistoryItem(
        action: title,
        provider: provider,
        original: text,
        result: cachedResult,
      );

      return;
    }

    final prompt = _aiService.buildPrompt(action, text);
    final requestVersion = _aiRequestVersion;

    setState(() {
      isLoading = true;
      resultTitle = '$title - $provider';
      resultText = '';
    });

    try {
      final parsed = await _aiService.callSelectedAi(
        provider: selectedProvider,
        prompt: prompt,
      );

      if (!mounted || requestVersion != _aiRequestVersion) return;

      cache[cacheKey] = parsed;
      await _storageService.saveCache(cache);

      if (!mounted || requestVersion != _aiRequestVersion) return;

      setState(() {
        resultText = parsed;
      });

      await _saveHistoryItem(
        action: title,
        provider: provider,
        original: text,
        result: parsed,
      );
    } catch (e) {
      if (!mounted || requestVersion != _aiRequestVersion) return;

      setState(() {
        resultTitle = 'Errore';
        resultText = e.toString();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore AI: $e')));
    } finally {
      if (mounted && requestVersion == _aiRequestVersion) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _scheduleAutoTranslate(String newText) {
    _autoTranslateTimer?.cancel();

    if (!autoTranslate) return;
    if (newText.trim().isEmpty) return;
    if (isLoading) return;

    _autoTranslateTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (!autoTranslate) return;

      final text = _limitedSelectedText();
      if (text.isEmpty) return;

      final provider = _aiService.providerName(selectedProvider);

      final key = _aiService.makeCacheKey(
        action: 'traduci',
        provider: provider,
        text: text,
      );

      if (key == lastAutoTranslateKey) return;

      lastAutoTranslateKey = key;
      _askAi('traduci');
    });
  }

  void _showActionPopup() {
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
                    _askAi('traduci');
                  },
                  icon: const Icon(Icons.translate),
                  label: const Text('Traduci'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _askAi('spiega');
                  },
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Spiega'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _askAi('riassumi');
                  },
                  icon: const Icon(Icons.short_text),
                  label: const Text('Riassumi'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _askAi('vocabolario');
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

  void _clearSelection() {
    _autoTranslateTimer?.cancel();

    setState(() {
      selectedText = '';
      selectedTextScrollOffset = null;
      _selectionClearVersion++;
    });
  }

  void _openHistoryItem(HistoryItem item) {
    Navigator.pop(context);

    final chapterIndex = item.page - 1;
    final hasValidChapter =
        chapterIndex >= 0 && chapterIndex < widget.book.chapters.length;

    setState(() {
      if (hasValidChapter) {
        selectedChapterIndex = chapterIndex;
      }

      resultTitle = '${item.action} - ${item.provider} - capitolo ${item.page}';
      resultText = item.result;
    });

    final targetOffset = item.scrollOffset;

    if (targetOffset != null) {
      void jumpToSavedOffset() {
        if (!mounted || !_scrollController.hasClients) return;

        final position = _scrollController.position;
        final safeOffset = targetOffset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );

        _scrollController.jumpTo(safeOffset);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        jumpToSavedOffset();
      });

      Future.delayed(const Duration(milliseconds: 120), () {
        jumpToSavedOffset();
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        jumpToSavedOffset();
      });

      return;
    }

    if (!hasValidChapter) return;

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _scrollToChapter(chapterIndex);
    });
  }

  void clearAll() {
    _autoTranslateTimer?.cancel();

    setState(() {
      selectedText = '';
      selectedTextScrollOffset = null;
      resultText = '';
      resultTitle = 'Risultato';
      lastAutoTranslateKey = '';
      _selectionClearVersion++;
    });
  }

  void resetToHome() {
    _autoTranslateTimer?.cancel();
    _savePositionDebounce?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PdfTranslatorPage()),
    );
  }

  Future<void> _restoreReadingPosition() async {
    final offset = await _storageService.loadSavedEpubScrollOffset(
      _epubStorageKey,
    );

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      final restoredOffset = offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      _scrollController.jumpTo(restoredOffset);
    });
  }

  void _saveReadingPositionSoon() {
    _savePositionDebounce?.cancel();
    _savePositionDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!_scrollController.hasClients) return;

      _storageService.saveEpubScrollOffset(
        epubStorageKey: _epubStorageKey,
        scrollOffset: _scrollController.offset,
      );
    });
  }

  void _scrollToChapter(int index) {
    if (index < 0 || index >= _chapterKeys.length) return;

    if (mounted) {
      setState(() {
        selectedChapterIndex = index;
      });
    }

    final chapterContext = _chapterKeys[index].currentContext;
    if (chapterContext == null) return;

    Scrollable.ensureVisible(
      chapterContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0,
    );
  }

  int _currentVisibleChapterIndex() {
    if (!_scrollController.hasClients || _chapterKeys.isEmpty) {
      return selectedChapterIndex;
    }

    final markerY = MediaQuery.of(context).size.height * 0.35;
    var currentIndex = selectedChapterIndex;

    for (var i = 0; i < _chapterKeys.length; i++) {
      final chapterContext = _chapterKeys[i].currentContext;
      if (chapterContext == null) continue;

      final renderObject = chapterContext.findRenderObject();
      if (renderObject is! RenderBox) continue;

      final chapterTop = renderObject.localToGlobal(Offset.zero).dy;

      if (chapterTop <= markerY) {
        currentIndex = i;
      } else {
        break;
      }
    }

    return currentIndex.clamp(0, _chapterKeys.length - 1);
  }

  @override
  void dispose() {
    _savePositionDebounce?.cancel();
    _autoTranslateTimer?.cancel();

    if (_scrollController.hasClients) {
      unawaited(
        _storageService.saveEpubScrollOffset(
          epubStorageKey: _epubStorageKey,
          scrollOffset: _scrollController.offset,
        ),
      );
    }

    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
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
            tooltip: 'Cronologia EPUB',
            icon: const Icon(Icons.history),
            onPressed: showEpubHistory,
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
          if (selectedText.trim().isNotEmpty)
            IconButton(
              tooltip: 'Cancella selezione',
              icon: const Icon(Icons.backspace_outlined),
              onPressed: _clearSelection,
            ),
          IconButton(
            tooltip: 'Capitoli',
            icon: const Icon(Icons.menu_book),
            onPressed: showChapterSelector,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(18),
              child: SelectionArea(
                key: ValueKey(_selectionClearVersion),
                onSelectionChanged: (selection) {
                  final newText = selection?.plainText ?? '';

                  final currentOffset = _scrollController.hasClients
                      ? _scrollController.offset
                      : null;

                  setState(() {
                    selectedText = newText;
                    selectedTextScrollOffset = newText.trim().isNotEmpty
                        ? currentOffset
                        : null;
                  });

                  _scheduleAutoTranslate(newText);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(widget.book.chapters.length, (index) {
                    final chapter = widget.book.chapters[index];

                    return Padding(
                      key: _chapterKeys[index],
                      padding: EdgeInsets.only(
                        bottom: index == widget.book.chapters.length - 1
                            ? 24
                            : 36,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapter.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            chapter.text,
                            style: const TextStyle(fontSize: 18, height: 1.5),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          TranslationPanel(
            selectedText: selectedText,
            resultText: resultText,
            resultTitle: resultTitle,
            isLoading: isLoading,
            currentPage: selectedChapterIndex + 1,
            autoTranslate: autoTranslate,
            selectedProvider: selectedProvider,
            locationLabel: 'capitolo ${selectedChapterIndex + 1}',
            emptySelectionMessage: 'Seleziona una frase nell\'EPUB',
            onProviderChanged: (value) {
              setState(() {
                selectedProvider = value;
                lastAutoTranslateKey = '';
              });

              _storageService.saveProvider(value);
            },
            onAutoTranslateChanged: (value) {
              setState(() {
                autoTranslate = value;
                lastAutoTranslateKey = '';
              });

              _storageService.saveAutoTranslate(value);

              if (value && selectedText.trim().isNotEmpty) {
                _scheduleAutoTranslate(selectedText);
              }
            },
            onShowActionPopup: _showActionPopup,
            onAskAi: _askAi,
            onOpenResult: openResultPage,
          ),
        ],
      ),
    );
  }
}
