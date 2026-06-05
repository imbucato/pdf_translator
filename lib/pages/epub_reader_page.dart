import 'dart:async';

import 'package:flutter/material.dart';

import '../services/epub_service.dart';
import '../services/storage_service.dart';
import 'result_page.dart';

class EpubReaderPage extends StatefulWidget {
  final EpubBookData book;

  const EpubReaderPage({super.key, required this.book});

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  final ScrollController _scrollController = ScrollController();
  final StorageService _storageService = StorageService();

  late final List<GlobalKey> _chapterKeys;
  late final String _epubStorageKey;

  Timer? _savePositionDebounce;
  int selectedChapterIndex = 0;
  String selectedText = '';
  String resultTitle = 'Risultato';
  String resultText = '';

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
  }

  void openResultPage() {
    if (resultText.trim().isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultPage(title: resultTitle, text: resultText),
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

  Future<void> fakeTranslateForNow() async {
    final text = selectedText.trim();

    if (text.isEmpty) return;

    setState(() {
      resultTitle = 'EPUB selezione';
      resultText = text;
    });
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
    final hasSelection = selectedText.trim().isNotEmpty;
    final hasResult = resultText.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
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
            child: SelectionArea(
              onSelectionChanged: (selection) {
                setState(() {
                  selectedText = selection?.plainText ?? '';
                });
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(18),
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
                  Text(
                    hasSelection
                        ? 'Testo selezionato: ${selectedText.length} caratteri'
                        : 'Seleziona testo nel capitolo',
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
                    FilledButton.icon(
                      onPressed: fakeTranslateForNow,
                      icon: const Icon(Icons.check),
                      label: const Text('Test selezione'),
                    ),
                  ],
                  if (hasResult) ...[
                    const SizedBox(height: 12),
                    Text(
                      resultTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: openResultPage,
                      icon: const Icon(Icons.open_in_full),
                      label: const Text('Apri risultato'),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: SingleChildScrollView(
                        child: SelectableText(resultText),
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
