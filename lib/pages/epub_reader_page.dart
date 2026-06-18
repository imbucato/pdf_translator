import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/bookmark_item.dart';
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
  final String? documentPath;
  final int? initialChapterIndex;
  final double? initialChapterAlignment;

  const EpubReaderPage({
    super.key,
    required this.book,
    this.documentPath,
    this.initialChapterIndex,
    this.initialChapterAlignment,
  });

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  static const double _epubBookmarkBucketSize = 0.25;
  static const double _readingProgressUpdateThreshold = 0.005;

  final AiService _aiService = AiService();
  final StorageService _storageService = StorageService();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  late final String _epubStorageKey;
  late final Stopwatch _epubPerfStopwatch;

  Timer? _savePositionDebounce;
  Timer? _autoTranslateTimer;
  int selectedChapterIndex = 0;
  double _readingProgress = 0.0;
  double epubFontSize = 18.0;
  double epubHorizontalPadding = 18.0;
  double epubLineHeight = 1.5;
  String epubReadingTheme = 'light';
  String epubFontFamily = 'default';
  String epubTextAlign = 'left';
  String selectedText = '';
  String resultTitle = 'Risultato';
  String resultText = '';
  String lastAutoTranslateKey = '';

  bool isLoading = false;
  bool autoTranslate = false;
  bool _didLogEpubContentBuild = false;

  AiProvider selectedProvider = AiProvider.openai;
  Map<String, String> cache = {};
  List<HistoryItem> history = [];
  List<BookmarkItem> bookmarks = [];
  int _aiRequestVersion = 0;

  static const double _minEpubFontSize = 14.0;
  static const double _maxEpubFontSize = 28.0;
  static const double _epubFontSizeStep = 1.0;
  static const double _minEpubHorizontalPadding = 0.0;
  static const double _maxEpubHorizontalPadding = 64.0;
  static const List<double> _epubLineHeightValues = [1.3, 1.5, 1.7, 1.9];
  static const List<String> _epubReadingThemeValues = [
    'light',
    'sepia',
    'dark',
  ];
  static const List<String> _epubFontFamilyValues = [
    'default',
    'serif',
    'sans',
  ];
  static const List<String> _epubTextAlignValues = ['left', 'justify'];

  @override
  void initState() {
    super.initState();

    _epubPerfStopwatch = Stopwatch()..start();
    _epubStorageKey = _storageService.makeEpubStorageKey(widget.book.title);

    _itemPositionsListener.itemPositions.addListener(
      _handleVisibleChapterPositionsChanged,
    );
    _restoreReadingPosition();
    _loadSettings();
    _loadCache();
    _loadHistory();
    _loadBookmarks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kDebugMode) return;

      final totalTextLength = widget.book.chapters.fold<int>(
        0,
        (total, chapter) => total + chapter.text.length,
      );

      debugPrint(
        '[EPUB PERF] chapters: ${widget.book.chapters.length}, '
        'chars: $totalTextLength',
      );
      debugPrint(
        '[EPUB PERF] first frame: ${_epubPerfStopwatch.elapsedMilliseconds} ms',
      );
    });
  }

  Future<void> _loadSettings() async {
    final provider = await _storageService.loadProvider();
    final savedAutoTranslate = await _storageService.loadAutoTranslate();
    final savedEpubFontSize = await _storageService.loadEpubFontSize();
    final savedEpubHorizontalPadding = await _storageService
        .loadEpubHorizontalPadding();
    final savedEpubLineHeight = await _storageService.loadEpubLineHeight();
    final savedEpubReadingTheme = await _storageService.loadEpubReadingTheme();
    final savedEpubFontFamily = await _storageService.loadEpubFontFamily();
    final savedEpubTextAlign = await _storageService.loadEpubTextAlign();

    if (!mounted) return;

    setState(() {
      selectedProvider = provider;
      autoTranslate = savedAutoTranslate;
      epubFontSize = savedEpubFontSize
          .clamp(_minEpubFontSize, _maxEpubFontSize)
          .toDouble();
      epubHorizontalPadding =
          savedEpubHorizontalPadding >= _minEpubHorizontalPadding &&
              savedEpubHorizontalPadding <= _maxEpubHorizontalPadding
          ? savedEpubHorizontalPadding
          : 18.0;
      epubLineHeight = _epubLineHeightValues.contains(savedEpubLineHeight)
          ? savedEpubLineHeight
          : 1.5;
      epubReadingTheme = _epubReadingThemeValues.contains(savedEpubReadingTheme)
          ? savedEpubReadingTheme
          : 'light';
      epubFontFamily = _epubFontFamilyValues.contains(savedEpubFontFamily)
          ? savedEpubFontFamily
          : 'default';
      epubTextAlign = _epubTextAlignValues.contains(savedEpubTextAlign)
          ? savedEpubTextAlign
          : 'left';
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

  Future<void> _loadBookmarks() async {
    final savedBookmarks = await _storageService.getBookmarks();

    if (!mounted) return;

    setState(() {
      bookmarks = savedBookmarks;
    });
  }

  Future<void> openResultPage() async {
    if (resultText.trim().isEmpty) return;

    final savedLocation = _currentVisibleChapterLocation();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultPage(title: resultTitle, text: resultText),
      ),
    );

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreChapterLocation(savedLocation);
    });

    await Future.delayed(const Duration(milliseconds: 80));
    _restoreChapterLocation(savedLocation);
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
                  _jumpToChapter(index);
                },
              );
            },
          ),
        );
      },
    );
  }

  String _chapterLabelForIndex(int chapterIndex) {
    if (chapterIndex >= 0 && chapterIndex < widget.book.chapters.length) {
      final chapterTitle = widget.book.chapters[chapterIndex].title.trim();

      if (chapterTitle.isNotEmpty) return chapterTitle;
    }

    return 'Capitolo ${chapterIndex + 1}';
  }

  String _currentChapterLabel() {
    return _chapterLabelForIndex(selectedChapterIndex);
  }

  BookmarkItem? _currentEpubBookmark() {
    final path = widget.documentPath;
    if (path == null) return null;

    final location = _currentVisibleChapterLocation();
    final positionInChapter = _epubPositionInChapter(location.alignment);

    for (final bookmark in bookmarks) {
      if (bookmark.documentType == 'epub' &&
          bookmark.documentPath == path &&
          bookmark.chapterIndex == location.index &&
          _epubBookmarkBucket(bookmark.epubPositionInChapter) ==
              _epubBookmarkBucket(positionInChapter)) {
        return bookmark;
      }
    }

    return null;
  }

  Future<void> _toggleCurrentEpubBookmark() async {
    final path = widget.documentPath;
    if (path == null || path.isEmpty || widget.book.chapters.isEmpty) return;

    final existingBookmark = _currentEpubBookmark();

    if (existingBookmark != null) {
      await _storageService.removeBookmark(existingBookmark.id);
      await _loadBookmarks();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Segnalibro rimosso')));
      return;
    }

    final location = _currentVisibleChapterLocation();
    final chapterIndex = location.index;
    final chapterTitle = _chapterLabelForIndex(chapterIndex);
    final positionInChapter = _epubPositionInChapter(location.alignment);

    await _storageService.addBookmark(
      BookmarkItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        documentPath: path,
        documentName: _documentNameFromPath(path),
        documentType: 'epub',
        createdAt: DateTime.now(),
        chapterIndex: chapterIndex,
        chapterTitle: chapterTitle,
        epubAlignment: location.alignment,
        epubPositionInChapter: positionInChapter,
        positionLabel: '$chapterTitle - punto salvato',
      ),
    );
    await _loadBookmarks();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Segnalibro aggiunto')));
  }

  String _limitedSelectedText() {
    final text = TextCleanerService.normalizePdfText(selectedText);

    if (text.length <= 1200) return text;

    return text.substring(0, 1200);
  }

  double _epubPositionInChapter(double alignment) {
    return (-alignment).clamp(0, double.infinity).toDouble();
  }

  int _epubBookmarkBucket(double? position) {
    final safePosition = (position ?? 0).clamp(0, double.infinity).toDouble();

    return (safePosition / _epubBookmarkBucketSize).round();
  }

  Future<void> _saveHistoryItem({
    required String action,
    required String provider,
    required String original,
    required String result,
  }) async {
    final chapterIndex = _currentVisibleChapterIndex();
    final chapterLabel = _chapterLabelForIndex(chapterIndex);

    final item = HistoryItem(
      pdfKey: _epubStorageKey,
      action: action,
      provider: provider,
      original: original,
      result: result,
      page: chapterIndex + 1,
      date: DateTime.now(),
      locationTitle: chapterLabel,
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

      final chapterLabel = item.locationTitle?.trim().isNotEmpty == true
          ? item.locationTitle!.trim()
          : _chapterLabelForIndex(chapterIndex);

      resultTitle = '${item.action} - ${item.provider} - $chapterLabel';
      resultText = item.result;
    });

    if (!hasValidChapter) return;

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _jumpToChapter(chapterIndex);
    });
  }

  void clearAll() {
    _autoTranslateTimer?.cancel();

    setState(() {
      selectedText = '';
      resultText = '';
      resultTitle = 'Risultato';
      lastAutoTranslateKey = '';
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
    if (widget.book.chapters.isEmpty) return;

    final savedChapterIndex = await _storageService.loadSavedEpubChapterIndex(
      _epubStorageKey,
    );
    final savedProgress = await _storageService.loadEpubProgress(
      _epubStorageKey,
    );

    if (!mounted) return;

    final fallbackChapterIndex =
        savedProgress == null || widget.book.chapters.length <= 1
        ? 0
        : ((savedProgress / 100) * (widget.book.chapters.length - 1)).round();

    final chapterIndex =
        (widget.initialChapterIndex ??
                savedChapterIndex ??
                fallbackChapterIndex)
            .clamp(0, widget.book.chapters.length - 1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToChapter(
        chapterIndex,
        duration: Duration.zero,
        alignment: widget.initialChapterAlignment ?? 0,
      );
    });
  }

  void _saveReadingPositionSoon() {
    _savePositionDebounce?.cancel();
    _savePositionDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveCurrentEpubPosition());
    });
  }

  Future<void> _saveCurrentEpubPosition() async {
    if (widget.book.chapters.isEmpty) return;

    final chapterIndex = _currentVisibleChapterIndex();

    await _storageService.saveEpubChapterIndex(
      epubStorageKey: _epubStorageKey,
      chapterIndex: chapterIndex,
    );

    final percent = (_currentReadingProgress() * 100).round().clamp(0, 100);

    await _storageService.saveEpubProgress(_epubStorageKey, percent);
  }

  void _jumpToChapter(
    int chapterIndex, {
    Duration duration = const Duration(milliseconds: 350),
    double alignment = 0,
  }) {
    if (widget.book.chapters.isEmpty ||
        chapterIndex < 0 ||
        chapterIndex >= widget.book.chapters.length) {
      return;
    }

    if (mounted && selectedChapterIndex != chapterIndex) {
      setState(() {
        selectedChapterIndex = chapterIndex;
        _readingProgress = _readingProgressForLocation((
          index: chapterIndex,
          alignment: alignment,
        ));
      });
    }

    void jump() {
      if (!mounted || !_itemScrollController.isAttached) return;

      if (duration == Duration.zero) {
        _itemScrollController.jumpTo(index: chapterIndex, alignment: alignment);
        return;
      }

      unawaited(
        _itemScrollController.scrollTo(
          index: chapterIndex,
          alignment: alignment,
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
      );
    }

    if (_itemScrollController.isAttached) {
      jump();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
    });
  }

  int _currentVisibleChapterIndex() {
    return _currentVisibleChapterLocation().index;
  }

  double _currentReadingProgress() {
    return _readingProgressForLocation(_currentVisibleChapterLocation());
  }

  double _readingProgressForLocation(({double alignment, int index}) location) {
    final chapterCount = widget.book.chapters.length;
    if (chapterCount <= 0) return 0;
    if (chapterCount == 1) {
      return _epubPositionInChapter(location.alignment).clamp(0, 1).toDouble();
    }

    final chapterIndex = location.index.clamp(0, chapterCount - 1);
    final positionInChapter = _epubPositionInChapter(
      location.alignment,
    ).clamp(0, 1).toDouble();

    return ((chapterIndex + positionInChapter) / chapterCount)
        .clamp(0, 1)
        .toDouble();
  }

  ({double alignment, int index}) _currentVisibleChapterLocation() {
    if (widget.book.chapters.isEmpty) {
      return (index: 0, alignment: 0);
    }

    final visiblePositions = _itemPositionsListener.itemPositions.value
        .where(
          (position) =>
              position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
        )
        .toList();

    if (visiblePositions.isEmpty) {
      return (index: selectedChapterIndex, alignment: 0);
    }

    visiblePositions.sort(
      (a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge),
    );
    final currentPosition = visiblePositions.first;

    return (
      index: currentPosition.index.clamp(0, widget.book.chapters.length - 1),
      alignment: currentPosition.itemLeadingEdge,
    );
  }

  void _restoreChapterLocation(({double alignment, int index}) location) {
    _jumpToChapter(
      location.index,
      duration: Duration.zero,
      alignment: location.alignment,
    );
  }

  void _handleVisibleChapterPositionsChanged() {
    final location = _currentVisibleChapterLocation();
    final chapterIndex = location.index;
    final readingProgress = _readingProgressForLocation(location);
    final didProgressChange =
        (readingProgress - _readingProgress).abs() >=
        _readingProgressUpdateThreshold;

    if ((chapterIndex != selectedChapterIndex || didProgressChange) &&
        mounted) {
      setState(() {
        selectedChapterIndex = chapterIndex;
        _readingProgress = readingProgress;
      });
    }

    _saveReadingPositionSoon();
  }

  @override
  void dispose() {
    _savePositionDebounce?.cancel();
    _autoTranslateTimer?.cancel();
    _itemPositionsListener.itemPositions.removeListener(
      _handleVisibleChapterPositionsChanged,
    );
    unawaited(_saveCurrentEpubPosition());
    super.dispose();
  }

  void _setEpubFontSize(double value) {
    final nextFontSize = value
        .clamp(_minEpubFontSize, _maxEpubFontSize)
        .toDouble();

    if (nextFontSize == epubFontSize) return;

    _updateReadingAppearance(() {
      epubFontSize = nextFontSize;
    });

    unawaited(_storageService.saveEpubFontSize(nextFontSize));
  }

  void _changeEpubFontSize(double delta) {
    _setEpubFontSize(epubFontSize + delta);
  }

  void _changeEpubHorizontalPadding(double value) {
    final nextPadding = value
        .clamp(_minEpubHorizontalPadding, _maxEpubHorizontalPadding)
        .toDouble();

    if (nextPadding == epubHorizontalPadding) return;

    _updateReadingAppearance(() {
      epubHorizontalPadding = nextPadding;
    });

    unawaited(_storageService.saveEpubHorizontalPadding(nextPadding));
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

  void _applyEpubComfortPreset(String value) {
    final preset = switch (value) {
      'compact' => (fontSize: 16.0, padding: 10.0, lineHeight: 1.3),
      'comfortable' => (fontSize: 20.0, padding: 26.0, lineHeight: 1.7),
      _ => (fontSize: 18.0, padding: 18.0, lineHeight: 1.5),
    };

    _updateReadingAppearance(() {
      epubFontSize = preset.fontSize;
      epubHorizontalPadding = preset.padding;
      epubLineHeight = preset.lineHeight;
    });

    unawaited(_storageService.saveEpubFontSize(preset.fontSize));
    unawaited(_storageService.saveEpubHorizontalPadding(preset.padding));
    unawaited(_storageService.saveEpubLineHeight(preset.lineHeight));
  }

  void _changeEpubFontFamily(String value) {
    if (!_epubFontFamilyValues.contains(value) || value == epubFontFamily) {
      return;
    }

    _updateReadingAppearance(() {
      epubFontFamily = value;
    });

    unawaited(_storageService.saveEpubFontFamily(value));
  }

  void _changeEpubTextAlign(String value) {
    if (!_epubTextAlignValues.contains(value) || value == epubTextAlign) {
      return;
    }

    _updateReadingAppearance(() {
      epubTextAlign = value;
    });

    unawaited(_storageService.saveEpubTextAlign(value));
  }

  void _updateReadingAppearance(VoidCallback update) {
    final savedLocation = _currentVisibleChapterLocation();

    setState(update);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreChapterLocation(savedLocation);
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

  String? _epubFontFamily() {
    return switch (epubFontFamily) {
      'serif' => 'serif',
      'sans' => 'sans-serif',
      _ => null,
    };
  }

  TextAlign _epubTextAlign() {
    return epubTextAlign == 'justify' ? TextAlign.justify : TextAlign.left;
  }

  void _handleEpubSelectionChanged(SelectedContent? selection) {
    final newText = selection?.plainText ?? '';

    setState(() {
      selectedText = newText;
    });

    _scheduleAutoTranslate(newText);
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
                    Text(
                      'Preset comfort',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        optionChip(
                          label: 'Compatto',
                          selected:
                              epubFontSize == 16.0 &&
                              epubHorizontalPadding == 10.0 &&
                              epubLineHeight == 1.3,
                          onSelected: () => _applyEpubComfortPreset('compact'),
                        ),
                        optionChip(
                          label: 'Normale',
                          selected:
                              epubFontSize == 18.0 &&
                              epubHorizontalPadding == 18.0 &&
                              epubLineHeight == 1.5,
                          onSelected: () => _applyEpubComfortPreset('normal'),
                        ),
                        optionChip(
                          label: 'Comodo',
                          selected:
                              epubFontSize == 20.0 &&
                              epubHorizontalPadding == 26.0 &&
                              epubLineHeight == 1.7,
                          onSelected: () =>
                              _applyEpubComfortPreset('comfortable'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Font',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        optionChip(
                          label: 'Predefinito',
                          selected: epubFontFamily == 'default',
                          onSelected: () => _changeEpubFontFamily('default'),
                        ),
                        optionChip(
                          label: 'Serif',
                          selected: epubFontFamily == 'serif',
                          onSelected: () => _changeEpubFontFamily('serif'),
                        ),
                        optionChip(
                          label: 'Sans',
                          selected: epubFontFamily == 'sans',
                          onSelected: () => _changeEpubFontFamily('sans'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Allineamento',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        optionChip(
                          label: 'Sinistra',
                          selected: epubTextAlign == 'left',
                          onSelected: () => _changeEpubTextAlign('left'),
                        ),
                        optionChip(
                          label: 'Giustificato',
                          selected: epubTextAlign == 'justify',
                          onSelected: () => _changeEpubTextAlign('justify'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Dimensione carattere',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${epubFontSize.round()}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    Slider(
                      value: epubFontSize
                          .clamp(_minEpubFontSize, _maxEpubFontSize)
                          .toDouble(),
                      min: _minEpubFontSize,
                      max: _maxEpubFontSize,
                      divisions: (_maxEpubFontSize - _minEpubFontSize).round(),
                      label: epubFontSize.round().toString(),
                      onChanged: (value) {
                        _setEpubFontSize(value);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Margini laterali',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${epubHorizontalPadding.round()} px',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    Slider(
                      value: epubHorizontalPadding
                          .clamp(
                            _minEpubHorizontalPadding,
                            _maxEpubHorizontalPadding,
                          )
                          .toDouble(),
                      min: _minEpubHorizontalPadding,
                      max: _maxEpubHorizontalPadding,
                      divisions: 16,
                      label: '${epubHorizontalPadding.round()} px',
                      onChanged: (value) {
                        _changeEpubHorizontalPadding(value);
                        setModalState(() {});
                      },
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
    final currentBookmark = _currentEpubBookmark();

    return AppBar(
      //title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: currentBookmark != null
              ? 'Rimuovi segnalibro'
              : 'Aggiungi segnalibro',
          icon: Icon(
            currentBookmark != null ? Icons.bookmark : Icons.bookmark_border,
          ),
          onPressed: widget.documentPath == null
              ? null
              : _toggleCurrentEpubBookmark,
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
          color: Theme.of(context).colorScheme.surface,
          onSelected: (value) {
            switch (value) {
              case 'font_minus':
                _changeEpubFontSize(-_epubFontSizeStep);
                break;
              case 'font_plus':
                _changeEpubFontSize(_epubFontSizeStep);
                break;
              case 'lettura':
                _showReadingSettingsSheet();
                break;
              case 'cache':
                clearCache();
                break;
              case 'credito':
                showCreditInfo();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'font_minus',
              child: Row(
                children: [
                  Icon(
                    Icons.text_decrease,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Riduci carattere',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'font_plus',
              child: Row(
                children: [
                  Icon(
                    Icons.text_increase,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Aumenta carattere',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
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
    if (!_didLogEpubContentBuild) {
      _didLogEpubContentBuild = true;

      if (kDebugMode) {
        debugPrint('[EPUB PERF] EPUB content first built');
      }
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textColor = _readingTextColor(colorScheme);
    final fontFamily = _epubFontFamily();
    final textAlign = _epubTextAlign();

    return ColoredBox(
      color: _readingBackgroundColor(colorScheme),
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        padding: EdgeInsets.symmetric(
          horizontal: epubHorizontalPadding,
          vertical: 8,
        ),
        itemCount: widget.book.chapters.length,
        itemBuilder: (context, index) {
          final chapter = widget.book.chapters[index];

          return SelectionArea(
            onSelectionChanged: _handleEpubSelectionChanged,
            child: Padding(
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
                    textAlign: textAlign,
                    style: TextStyle(
                      color: textColor,
                      fontFamily: fontFamily,
                      fontSize: epubFontSize,
                      height: epubLineHeight,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
      locationLabel: _currentChapterLabel(),
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

  Widget _buildReadingProgressBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = _readingBackgroundColor(colorScheme);
    final textColor = _readingTextColor(colorScheme);
    final progress = _readingProgress.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round().clamp(0, 100);
    final chapterTitle = _currentChapterLabel();
    final label = chapterTitle.trim().isEmpty
        ? '$percent%'
        : '$percent% · $chapterTitle';

    return ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: textColor.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: progress,
                  backgroundColor: textColor.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary.withValues(alpha: 0.82),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildEpubAppBar(),
      body: Column(
        children: [
          _buildReadingProgressBar(),
          Expanded(child: _buildEpubContent()),
          _buildTranslationPanel(),
        ],
      ),
    );
  }
}
