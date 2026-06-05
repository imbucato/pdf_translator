import 'package:flutter/material.dart';

import '../services/ai_service.dart';

class TranslationPanel extends StatelessWidget {
  const TranslationPanel({
    super.key,
    required this.selectedText,
    required this.resultText,
    required this.resultTitle,
    required this.isLoading,
    required this.currentPage,
    required this.autoTranslate,
    required this.selectedProvider,
    required this.onProviderChanged,
    required this.onAutoTranslateChanged,
    required this.onShowActionPopup,
    required this.onAskAi,
    required this.onOpenResult,
    this.locationLabel,
    this.emptySelectionMessage,
  });

  final String selectedText;
  final String resultText;
  final String resultTitle;
  final bool isLoading;
  final int currentPage;
  final bool autoTranslate;
  final AiProvider selectedProvider;
  final ValueChanged<AiProvider> onProviderChanged;
  final ValueChanged<bool> onAutoTranslateChanged;
  final VoidCallback onShowActionPopup;
  final ValueChanged<String> onAskAi;
  final VoidCallback onOpenResult;
  final String? locationLabel;
  final String? emptySelectionMessage;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedText.trim().isNotEmpty;
    final isLimited = selectedText.trim().length > 1200;
    final selectedLocationLabel = locationLabel ?? 'pagina $currentPage';
    final noSelectionMessage =
        emptySelectionMessage ??
        'Pagina $currentPage - seleziona una frase nel PDF';

    return Container(
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

                          onProviderChanged(value);
                        },
                ),
                const Spacer(),
                const Text('Auto'),
                Switch(value: autoTranslate, onChanged: onAutoTranslateChanged),
              ],
            ),
            Text(
              hasSelection
                  ? 'Testo selezionato: ${selectedText.length} caratteri - $selectedLocationLabel'
                  : noSelectionMessage,
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
                    onPressed: isLoading ? null : onShowActionPopup,
                    icon: const Icon(Icons.touch_app),
                    label: const Text('Azioni'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : () => onAskAi('traduci'),
                    icon: const Icon(Icons.translate),
                    label: const Text('Traduci'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : () => onAskAi('spiega'),
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Spiega'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : () => onAskAi('riassumi'),
                    icon: const Icon(Icons.short_text),
                    label: const Text('Riassumi'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : () => onAskAi('vocabolario'),
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
                  onPressed: onOpenResult,
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
    );
  }
}
