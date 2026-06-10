import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import '../models/history_item.dart';
import '../models/recent_document.dart';
import '../services/ai_service.dart';
import '../services/epub_service.dart';
import '../services/storage_service.dart';
import '../services/text_cleaner_service.dart';
import '../widgets/translation_panel.dart';
import 'history_page.dart';
import 'home_page.dart';
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
  double epubFontSize = 18.0;
  double epubHorizontalPadding = 18.0;
  double epubLineHeight = 1.5;
  String epubReadingTheme = 'light';
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

  static const double _minEpubFontSize = 14.0;
  static const double _maxEpubFontSize = 28.0;
  static const double _epubFontSizeStep = 1.0;
  static const List<double> _epubHorizontalPaddingValues = [
    12.0,
    18.0,
    24.0,
    32.0,
  ];
  static const List<double> _epubLineHeightValues = [1.3, 1.5, 1.7, 1.9];
  static const List<String> _epubReadingThemeValues = [
    'light',
    'sepia',
    'dark',
  ];

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
    final savedEpubFontSize = await _storageService.loadEpubFontSize();
    final savedEpubHorizontalPadding = await _storageService
        .loadEpubHorizontalPadding();
    final savedEpubLineHeight = await _storageService.loadEpubLineHeight();
    final savedEpubReadingTheme = await _storageService.loadEpubReadingTheme();

    if (!mounted) return;

    setState(() {
      selectedProvider = provider;
      autoTranslate = savedAutoTranslate;
      epubFontSize = savedEpubFontSize
          .clamp(_minEpubFontSize, _maxEpubFontSize)
          .toDouble();
      epubHorizontalPadding =
          _epubHorizontalPaddingValues.contains(savedEpubHorizontalPadding)
          ? savedEpubHorizontalPadding
          : 18.0;
      epubLineHeight = _epubLineHeightValues.contains(savedEpubLineHeight)
          ? savedEpubLineHeight
          : 1.5;
      epubReadingTheme = _epubReadingThemeValues.contains(savedEpubReadingTheme)
          ? savedEpubReadingTheme
          : 'light';
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

      if (!file.existsSync()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File non trovato')));
        return;
      }

      await _addRecentDocument(path: path, type: 'pdf');

      if (!mounted) return;

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

    if (!file.existsSync()) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File non trovato')));
      return;
    }

    try {
      final book = await EpubService().readEpub(file);

      if (!mounted) return;

      await _addRecentDocument(path: path, type: 'epub');

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

  String _documentNameFromPath(String path) {
    return path.split(Platform.pathSeparator).last;
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

    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }

    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
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

  void _changeEpubFontSize(double delta) {
    final nextFontSize = (epubFontSize + delta)
        .clamp(_minEpubFontSize, _maxEpubFontSize)
        .toDouble();

    if (nextFontSize == epubFontSize) return;

    _updateReadingAppearance(() {
      epubFontSize = nextFontSize;
    });

    unawaited(_storageService.saveEpubFontSize(nextFontSize));
  }

  void _changeEpubHorizontalPadding(double value) {
    if (value == epubHorizontalPadding) return;

    _updateReadingAppearance(() {
      epubHorizontalPadding = value;
    });

    unawaited(_storageService.saveEpubHorizontalPadding(value));
  }

  void _changeEpubLineHeight(double value) {
    if (value == epubLineHeight) return;

    _updateReadingAppearance(() {
      epubLineHeight = value;
    });

    unawaited(_storageService.saveEpubLineHeight(value));
  }

  void _changeEpubReadingTheme(String value) {
    if (value == epubReadingTheme) return;

    _updateReadingAppearance(() {
      epubReadingTheme = value;
    });

    unawaited(_storageService.saveEpubReadingTheme(value));
  }

  void _updateReadingAppearance(VoidCallback update) {
    final savedOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;

    setState(update);

    if (savedOffset == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      final restoredOffset = savedOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      _scrollController.jumpTo(restoredOffset);
    });
  }

  Color _readingBackgroundColor(ColorScheme colorScheme) {
    switch (epubReadingTheme) {
      case 'sepia':
        return const Color(0xFFF4ECD8);
      case 'dark':
        return const Color(0xFF121212);
      case 'light':
      default:
        return colorScheme.surface;
    }
  }

  Color _readingTextColor(ColorScheme colorScheme) {
    switch (epubReadingTheme) {
      case 'sepia':
        return const Color(0xFF3B2F24);
      case 'dark':
        return const Color(0xFFEAEAEA);
      case 'light':
      default:
        return colorScheme.onSurface;
    }
  }

  void _showReadingSettingsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget optionChip({
              required String label,
              required bool selected,
              required VoidCallback onSelected,
            }) {
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) {
                  onSelected();
                  setModalState(() {});
                },
              );
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Impostazioni lettura',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Riduci carattere',
                          icon: const Icon(Icons.text_decrease),
                          onPressed: () {
                            _changeEpubFontSize(-_epubFontSizeStep);
                            setModalState(() {});
                          },
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              epubFontSize.toStringAsFixed(0),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Aumenta carattere',
                          icon: const Icon(Icons.text_increase),
                          onPressed: () {
                            _changeEpubFontSize(_epubFontSizeStep);
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Margini',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        optionChip(
                          label: 'Stretti',
                          selected: epubHorizontalPadding == 12.0,
                          onSelected: () => _changeEpubHorizontalPadding(12.0),
                        ),
                        optionChip(
                          label: 'Normali',
                          selected: epubHorizontalPadding == 18.0,
                          onSelected: () => _changeEpubHorizontalPadding(18.0),
                        ),
                        optionChip(
                          label: 'Larghi',
                          selected: epubHorizontalPadding == 24.0,
                          onSelected: () => _changeEpubHorizontalPadding(24.0),
                        ),
                        optionChip(
                          label: 'Molto larghi',
                          selected: epubHorizontalPadding == 32.0,
                          onSelected: () => _changeEpubHorizontalPadding(32.0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Interlinea',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final value in _epubLineHeightValues)
                          optionChip(
                            label: value.toStringAsFixed(1),
                            selected: epubLineHeight == value,
                            onSelected: () => _changeEpubLineHeight(value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tema',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        optionChip(
                          label: 'Chiaro',
                          selected: epubReadingTheme == 'light',
                          onSelected: () => _changeEpubReadingTheme('light'),
                        ),
                        optionChip(
                          label: 'Seppia',
                          selected: epubReadingTheme == 'sepia',
                          onSelected: () => _changeEpubReadingTheme('sepia'),
                        ),
                        optionChip(
                          label: 'Scuro',
                          selected: epubReadingTheme == 'dark',
                          onSelected: () => _changeEpubReadingTheme('dark'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  PreferredSizeWidget _buildEpubAppBar() {
    return AppBar(
      //title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Home',
          icon: const Icon(Icons.home_outlined),
          onPressed: resetToHome,
        ),
        IconButton(
          tooltip: 'Cronologia EPUB',
          icon: const Icon(Icons.history),
          onPressed: showEpubHistory,
        ),
        IconButton(
          tooltip: 'Apri PDF o EPUB',
          icon: const Icon(Icons.folder_open),
          onPressed: pickDocument,
        ),
        IconButton(
          tooltip: 'Riduci carattere',
          icon: const Icon(Icons.text_decrease),
          onPressed: () => _changeEpubFontSize(-_epubFontSizeStep),
        ),
        IconButton(
          tooltip: 'Aumenta carattere',
          icon: const Icon(Icons.text_increase),
          onPressed: () => _changeEpubFontSize(_epubFontSizeStep),
        ),
        IconButton(
          tooltip: 'Pulisci',
          icon: const Icon(Icons.clear),
          onPressed: clearAll,
        ),
        IconButton(
          tooltip: 'Capitoli',
          icon: const Icon(Icons.menu_book),
          onPressed: showChapterSelector,
        ),

        PopupMenuButton<String>(
          tooltip: 'Altro',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'credito':
                showCreditInfo();
                break;
              case 'cache':
                clearCache();
                break;
              case 'lettura':
                _showReadingSettingsSheet();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'lettura',
              child: Text('Impostazioni lettura'),
            ),
            const PopupMenuItem(value: 'credito', child: Text('Credito')),
            const PopupMenuItem(value: 'cache', child: Text('Svuota cache')),
          ],
        ),
      ],
    );
  }

  Widget _buildEpubContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = _readingTextColor(colorScheme);

    return ColoredBox(
      color: _readingBackgroundColor(colorScheme),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(
          horizontal: epubHorizontalPadding,
          vertical: 18,
        ),
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
                  bottom: index == widget.book.chapters.length - 1 ? 24 : 36,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chapter.title,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(color: textColor),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      chapter.text,
                      style: TextStyle(
                        color: textColor,
                        fontSize: epubFontSize,
                        height: epubLineHeight,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildTranslationPanel() {
    return TranslationPanel(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildEpubAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildEpubContent()),
          _buildTranslationPanel(),
        ],
      ),
    );
  }
}
