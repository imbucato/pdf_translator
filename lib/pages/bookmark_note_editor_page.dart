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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveNote() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.bookmarkTitle?.trim();
    final subtitle = widget.bookmarkSubtitle?.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nota segnalibro'),
        actions: [TextButton(onPressed: _saveNote, child: const Text('Salva'))],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null && title.isNotEmpty) ...[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Scrivi una nota opzionale',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saveNote,
                    child: const Text('Salva'),
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
