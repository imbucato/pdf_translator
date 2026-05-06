import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResultPage extends StatelessWidget {
  final String title;
  final String text;

  const ResultPage({super.key, required this.title, required this.text});

  Future<void> copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Risultato copiato negli appunti')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Copia',
            icon: const Icon(Icons.copy),
            onPressed: () => copyToClipboard(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 18, height: 1.45),
          ),
        ),
      ),
    );
  }
}
