import 'package:flutter/material.dart';

class BookmarkNoteEditorPage extends StatefulWidget {
  final String initialNote;
  final String? bookmarkTitle;
  final String? bookmarkSubtitle;

  const BookmarkNoteEditorPage({
    super.key,
    this.initialNote = '',
    this.bookmarkTitle,
    this.bookmarkSubtitle,
  });

  @override
  State<BookmarkNoteEditorPage> createState() => _BookmarkNoteEditorPageState();
}

class _BookmarkNoteEditorPageState extends State<BookmarkNoteEditorPage> {
  late final TextEditingController _controller;
  late final bool _hasInitialNote;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
    _hasInitialNote = widget.initialNote.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveNote() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  void _clearNote() {
    Navigator.of(context).pop('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = widget.bookmarkTitle?.trim();
    final subtitle = widget.bookmarkSubtitle?.trim();
    final hasContextTitle = title != null && title.isNotEmpty;
    final hasContextSubtitle = subtitle != null && subtitle.isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Nota segnalibro'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _saveNote,
              icon: const Icon(Icons.check),
              label: const Text('Salva'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primaryContainer.withValues(alpha: 0.88),
                      colorScheme.secondaryContainer.withValues(alpha: 0.72),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.bookmark, color: colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hasContextTitle ? title : 'Segnalibro',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          if (hasContextSubtitle) ...[
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onPrimaryContainer
                                    .withValues(alpha: 0.74),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.58,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                      decoration: InputDecoration(
                        hintText:
                            'Scrivi una nota personale su questo segnalibro...',
                        hintStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.72,
                          ),
                        ),
                        filled: true,
                        fillColor: colorScheme.surface.withValues(alpha: 0.82),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: colorScheme.primary.withValues(alpha: 0.55),
                            width: 1.4,
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (_hasInitialNote)
                    TextButton.icon(
                      onPressed: _clearNote,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Cancella nota'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saveNote,
                    icon: const Icon(Icons.check),
                    label: const Text('Salva'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
