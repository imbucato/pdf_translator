import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../services/storage_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final StorageService _storageService = StorageService();

  AiProvider _selectedProvider = AiProvider.openai;
  bool _autoTranslate = false;
  String _epubReadingTheme = 'light';
  bool _isLoading = true;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final provider = await _storageService.loadProvider();
    final autoTranslate = await _storageService.loadAutoTranslate();
    final epubReadingTheme = await _storageService.loadEpubReadingTheme();

    if (!mounted) return;

    setState(() {
      _selectedProvider = provider;
      _autoTranslate = autoTranslate;
      _epubReadingTheme = _validEpubTheme(epubReadingTheme);
      _isLoading = false;
    });
  }

  String _validEpubTheme(String value) {
    return switch (value) {
      'sepia' || 'dark' => value,
      _ => 'light',
    };
  }

  Future<void> _changeProvider(AiProvider? value) async {
    if (value == null || value == _selectedProvider) return;

    setState(() {
      _selectedProvider = value;
    });

    await _storageService.saveProvider(value);
  }

  Future<void> _changeAutoTranslate(bool value) async {
    setState(() {
      _autoTranslate = value;
    });

    await _storageService.saveAutoTranslate(value);
  }

  Future<void> _changeEpubReadingTheme(String value) async {
    if (value == _epubReadingTheme) return;

    setState(() {
      _epubReadingTheme = value;
    });

    await _storageService.saveEpubReadingTheme(value);
  }

  Future<void> _clearAiCache() async {
    setState(() {
      _isClearingCache = true;
    });

    await _storageService.clearCache();

    if (!mounted) return;

    setState(() {
      _isClearingCache = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cache AI svuotata')));
  }

  void _showAboutDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    final features = [
      'Lettura PDF',
      'Lettura EPUB',
      'Traduzione',
      'Spiegazione',
      'Riassunto',
      'Vocabolario',
      'Storico e documenti recenti',
    ];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          icon: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.auto_stories,
              color: colorScheme.onPrimaryContainer,
              size: 38,
            ),
          ),
          title: Text(
            'AI Reader',
            textAlign: TextAlign.center,
            style: Theme.of(
              dialogContext,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Leggi, traduci e approfondisci PDF ed EPUB',
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: features
                    .map(
                      (feature) => Chip(
                        avatar: const Icon(Icons.check_circle, size: 18),
                        label: Text(feature),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  String _providerLabel(AiProvider provider) {
    return switch (provider) {
      AiProvider.deepseek => 'DeepSeek',
      AiProvider.openai => 'OpenAI',
    };
  }

  String _epubThemeLabel(String value) {
    return switch (value) {
      'sepia' => 'Seppia',
      'dark' => 'Scuro',
      _ => 'Chiaro',
    };
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1.5,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.10),
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildAiSection(BuildContext context) {
    return _buildSection(
      context: context,
      title: 'AI',
      icon: Icons.auto_awesome,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Provider predefinito'),
          trailing: DropdownButton<AiProvider>(
            value: _selectedProvider,
            onChanged: _changeProvider,
            items: AiProvider.values
                .map(
                  (provider) => DropdownMenuItem(
                    value: provider,
                    child: Text(_providerLabel(provider)),
                  ),
                )
                .toList(),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-traduzione'),
          value: _autoTranslate,
          onChanged: _changeAutoTranslate,
        ),
      ],
    );
  }

  Widget _buildEpubSection(BuildContext context) {
    return _buildSection(
      context: context,
      title: 'EPUB',
      icon: Icons.menu_book,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tema lettura predefinito'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final theme in const ['light', 'sepia', 'dark'])
                  ChoiceChip(
                    label: Text(_epubThemeLabel(theme)),
                    selected: _epubReadingTheme == theme,
                    onSelected: (_) => _changeEpubReadingTheme(theme),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceSection(BuildContext context) {
    return _buildSection(
      context: context,
      title: 'Manutenzione',
      icon: Icons.cleaning_services,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cached),
          title: const Text('Svuota cache AI'),
          trailing: _isClearingCache
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Icon(Icons.chevron_right),
          onTap: _isClearingCache ? null : _clearAiCache,
        ),
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return _buildSection(
      context: context,
      title: 'Info',
      icon: Icons.info_outline,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.auto_stories),
          title: const Text('Info app'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showAboutDialog,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      backgroundColor: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.045),
        colorScheme.surface,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAiSection(context),
                        const SizedBox(height: 14),
                        _buildEpubSection(context),
                        const SizedBox(height: 14),
                        _buildMaintenanceSection(context),
                        const SizedBox(height: 14),
                        _buildInfoSection(context),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
