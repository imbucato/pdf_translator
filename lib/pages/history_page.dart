import 'package:flutter/material.dart';

import '../models/history_item.dart';

class HistoryPage extends StatefulWidget {
  final List<HistoryItem> history;
  final String? currentPdfKey;
  final void Function(HistoryItem item) onTapItem;
  final Future<void> Function(String type, List<HistoryItem> filteredHistory)
  onExportHistory;
  final Future<void> Function() onClearPdfHistory;
  final Future<void> Function(HistoryItem item) onDeleteItem;
  final String clearHistoryLabel;
  final String emptyHistoryLabel;
  final String locationLabel;

  const HistoryPage({
    super.key,
    required this.history,
    required this.currentPdfKey,
    required this.onTapItem,
    required this.onExportHistory,
    required this.onClearPdfHistory,
    required this.onDeleteItem,
    this.clearHistoryLabel = 'Svuota documento',
    this.emptyHistoryLabel = 'Nessuna cronologia per questo documento',
    this.locationLabel = 'pagina',
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String searchQuery = '';

  List<HistoryItem> get filteredHistory {
    final query = searchQuery.trim().toLowerCase();

    return widget.history.where((item) {
      final belongsToCurrentPdf = item.pdfKey == widget.currentPdfKey;

      if (!belongsToCurrentPdf) return false;
      if (query.isEmpty) return true;

      final itemLocationTitle = item.locationTitle?.trim() ?? '';
      final searchableText = [
        item.action,
        item.provider,
        itemLocationTitle,
        item.original,
        item.result,
        item.page.toString(),
      ].join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentHistory = filteredHistory;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Cerca nello storico',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    searchQuery = value;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        widget.onExportHistory('txt', currentHistory),
                    icon: const Icon(Icons.text_snippet),
                    label: const Text('TXT'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        widget.onExportHistory('markdown', currentHistory),
                    icon: const Icon(Icons.description),
                    label: const Text('Markdown'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        widget.onExportHistory('word', currentHistory),
                    icon: const Icon(Icons.article),
                    label: const Text('Word HTML'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onClearPdfHistory,
                    icon: const Icon(Icons.delete),
                    label: Text(widget.clearHistoryLabel),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: currentHistory.isEmpty
                  ? Center(child: Text(widget.emptyHistoryLabel))
                  : ListView.builder(
                      itemCount: currentHistory.length,
                      itemBuilder: (context, index) {
                        final item = currentHistory[index];
                        final itemLocationTitle =
                            item.locationTitle?.trim() ?? '';
                        final itemLocationLabel = itemLocationTitle.isNotEmpty
                            ? itemLocationTitle
                            : '${widget.locationLabel} ${item.page}';

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: ListTile(
                            title: Text(
                              '${item.action} · ${item.provider} - $itemLocationLabel',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                const Text(
                                  'Originale:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  item.original,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Risultato:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  item.result,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            onTap: () => widget.onTapItem(item),
                            onLongPress: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) {
                                  return AlertDialog(
                                    title: const Text('Elimina voce'),
                                    content: const Text(
                                      'Vuoi eliminare questa voce dallo storico?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context, false);
                                        },
                                        child: const Text('Annulla'),
                                      ),
                                      FilledButton(
                                        onPressed: () {
                                          Navigator.pop(context, true);
                                        },
                                        child: const Text('Elimina'),
                                      ),
                                    ],
                                  );
                                },
                              );

                              if (confirm == true) {
                                await widget.onDeleteItem(item);
                                if (mounted) {
                                  setState(() {});
                                }
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
