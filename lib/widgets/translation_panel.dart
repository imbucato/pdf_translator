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
      surfaceTintColor: colorScheme.surfaceTint,
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
                  color: isDisabled ? colorScheme.onSurfaceVariant : iconColor,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        const SizedBox(width: 5),
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.translate,
            label: 'Traduci',
            iconColor: colorScheme.primary,
            backgroundColor: colorScheme.primaryContainer.withValues(
              alpha: 0.62,
            ),
            onPressed: disabled ? null : () => onAskAi('traduci'),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.lightbulb_outline,
            label: 'Spiega',
            iconColor: const Color(0xFFB45309),
            backgroundColor: const Color(0xFFFFF7ED),
            onPressed: disabled ? null : () => onAskAi('spiega'),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.summarize,
            label: 'Sunto',
            iconColor: const Color(0xFF15803D),
            backgroundColor: const Color(0xFFF0FDF4),
            onPressed: disabled ? null : () => onAskAi('riassumi'),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.menu_book,
            label: 'Vocab.',
            iconColor: colorScheme.secondary,
            backgroundColor: colorScheme.secondaryContainer.withValues(
              alpha: 0.66,
            ),
            onPressed: disabled ? null : () => onAskAi('vocabolario'),
          ),
        ),
      ],
    );
  }

  IconData _resultIcon() {
    final normalizedTitle = resultTitle.toLowerCase();

    if (normalizedTitle.contains('traduci') ||
        normalizedTitle.contains('traduzione')) {
      return Icons.translate;
    }
    if (normalizedTitle.contains('spiega') ||
        normalizedTitle.contains('spiegazione')) {
      return Icons.lightbulb_outline;
    }
    if (normalizedTitle.contains('riassumi') ||
        normalizedTitle.contains('riassunto') ||
        normalizedTitle.contains('sunto')) {
      return Icons.summarize;
    }
    if (normalizedTitle.contains('vocabolario')) {
      return Icons.menu_book;
    }

    return Icons.auto_awesome;
  }

  Color _resultAccentColor(ColorScheme colorScheme) {
    final normalizedTitle = resultTitle.toLowerCase();

    if (normalizedTitle.contains('traduci') ||
        normalizedTitle.contains('traduzione')) {
      return colorScheme.primary;
    }
    if (normalizedTitle.contains('spiega') ||
        normalizedTitle.contains('spiegazione')) {
      return Colors.orange.shade800;
    }
    if (normalizedTitle.contains('riassumi') ||
        normalizedTitle.contains('riassunto') ||
        normalizedTitle.contains('sunto')) {
      return Colors.green.shade700;
    }
    if (normalizedTitle.contains('vocabolario')) {
      return colorScheme.secondary;
    }

    return colorScheme.primary;
  }

  Color _resultAccentBackground(ColorScheme colorScheme) {
    final normalizedTitle = resultTitle.toLowerCase();

    if (normalizedTitle.contains('traduci') ||
        normalizedTitle.contains('traduzione')) {
      return colorScheme.primaryContainer.withValues(alpha: 0.62);
    }
    if (normalizedTitle.contains('spiega') ||
        normalizedTitle.contains('spiegazione')) {
      return Colors.orange.shade50;
    }
    if (normalizedTitle.contains('riassumi') ||
        normalizedTitle.contains('riassunto') ||
        normalizedTitle.contains('sunto')) {
      return Colors.green.shade50;
    }
    if (normalizedTitle.contains('vocabolario')) {
      return colorScheme.secondaryContainer.withValues(alpha: 0.66);
    }

    return colorScheme.primaryContainer.withValues(alpha: 0.55);
  }

  Widget _buildResultArea(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = _resultAccentColor(colorScheme);
    final accentBackground = _resultAccentBackground(colorScheme);

    if (!isLoading && resultText.isEmpty) return const SizedBox.shrink();

    if (isLoading && resultText.isEmpty) {
      return Card(
        elevation: 1.5,
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainerLowest,
        shadowColor: colorScheme.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Elaborazione in corso...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      shadowColor: colorScheme.primary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accentBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_resultIcon(), size: 19, color: accentColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    resultTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Elaborazione in corso...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (resultText.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: SelectableText(
                    resultText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 15,
                      height: 1.38,
                    ),
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
                Icon(Icons.auto_awesome, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'AI',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<AiProvider>(
                    value: selectedProvider,
                    borderRadius: BorderRadius.circular(16),
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
                ),
                const Spacer(),
                Text(
                  'Auto',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Switch(value: autoTranslate, onChanged: onAutoTranslateChanged),
              ],
            ),
            Text(
              hasSelection
                  ? 'Testo selezionato: ${selectedText.length} caratteri - $selectedLocationLabel'
                  : noSelectionMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: hasSelection
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (isLimited)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Verranno inviati solo i primi 1200 caratteri.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.32,
                ),
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
