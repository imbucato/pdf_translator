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

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color iconColor,
    required Color backgroundColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDisabled = onPressed == null;

    return Material(
      color: isDisabled ? colorScheme.surfaceContainerHighest : backgroundColor,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isDisabled ? colorScheme.onSurfaceVariant : iconColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isDisabled
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionWrap(BuildContext context) {
    final disabled = isLoading;

    return Row(
      children: [
        const SizedBox(width: 5),
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.translate,
            label: 'Traduci',
            iconColor: Colors.blue.shade700,
            backgroundColor: Colors.blue.shade50,
            onPressed: disabled ? null : () => onAskAi('traduci'),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.lightbulb_outline,
            label: 'Spiega',
            iconColor: Colors.orange.shade800,
            backgroundColor: Colors.orange.shade50,
            onPressed: disabled ? null : () => onAskAi('spiega'),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.summarize,
            label: 'Sunto',
            iconColor: Colors.green.shade700,
            backgroundColor: Colors.green.shade50,
            onPressed: disabled ? null : () => onAskAi('riassumi'),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.menu_book,
            label: 'Vocab.',
            iconColor: Colors.purple.shade700,
            backgroundColor: Colors.purple.shade50,
            onPressed: disabled ? null : () => onAskAi('vocabolario'),
          ),
        ),
      ],
    );
  }

  Widget _buildResultArea(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!isLoading && resultText.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    resultText.isEmpty ? 'Risultato AI' : resultTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (resultText.isNotEmpty)
                  IconButton(
                    tooltip: 'Apri risultato',
                    icon: const Icon(Icons.open_in_full),
                    onPressed: onOpenResult,
                  ),
              ],
            ),
            if (isLoading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (resultText.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: SelectableText(
                    resultText,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.42),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
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
              const SizedBox(height: 8),
              Text(
                selectedText.length > 180
                    ? '${selectedText.substring(0, 180)}...'
                    : selectedText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              _buildActionWrap(context),
            ],
            if (isLoading || resultText.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildResultArea(context),
            ],
          ],
        ),
      ),
    );
  }
}
