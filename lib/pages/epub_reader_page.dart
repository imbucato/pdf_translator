import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../services/epub_service.dart';
import '../services/storage_service.dart';
import '../services/text_cleaner_service.dart';
import '../widgets/translation_panel.dart';
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

  bool isLoading = false;
  bool autoTranslate = false;

  AiProvider selectedProvider = AiProvider.openai;
  Map<String, String> cache = {};

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
    setState(() {
      cache.clear();
    });

    await _storageService.saveCache(cache);

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cache svuotata')));
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
      setState(() {
        resultTitle = '$title - $provider - cache';
        resultText = cache[cacheKey]!;
      });

      return;
    }

    final prompt = _aiService.buildPrompt(action, text);

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

      cache[cacheKey] = parsed;
      await _storageService.saveCache(cache);

      if (!mounted) return;

      setState(() {
        resultText = parsed;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        resultTitle = 'Errore';
        resultText = e.toString();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore AI: $e')));
    } finally {
      if (mounted) {
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
      _selectionClearVersion++;
    });
  }

  void clearAll() {
    _autoTranslateTimer?.cancel();

    setState(() {
      selectedText = '';
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

                  setState(() {
                    selectedText = newText;
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
