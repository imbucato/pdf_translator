import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/history_item.dart';

class ExportService {
  Future<File> exportHistory({
    required List<HistoryItem> history,
    required String type,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final extension = _extensionFor(type);
    final content = _contentFor(history: history, type: type);
    final file = File(
      '${dir.path}/pdf_translator_export_$timestamp.$extension',
    );

    await file.writeAsString(content, encoding: utf8);

    return file;
  }

  String _extensionFor(String type) {
    if (type == 'markdown') return 'md';
    if (type == 'word') return 'html';
    return 'txt';
  }

  String _contentFor({
    required List<HistoryItem> history,
    required String type,
  }) {
    if (type == 'markdown') {
      return history
          .map((item) {
            return '''
## ${item.action} Â· ${item.provider} - pagina ${item.page}

**Originale**

${item.original}

**Risultato**

${item.result}

---
''';
          })
          .join('\n');
    }

    if (type == 'word') {
      return '''
<html>
<head>
<meta charset="utf-8">
<title>PDF Translator Export</title>
</head>
<body>
<h1>Cronologia PDF Translator</h1>
${history.map((item) {
        return '''
<h2>${htmlEscape.convert(item.action)} Â· ${htmlEscape.convert(item.provider)} - pagina ${item.page}</h2>
<h3>Originale</h3>
<p>${htmlEscape.convert(item.original).replaceAll('\n', '<br>')}</p>
<h3>Risultato</h3>
<p>${htmlEscape.convert(item.result).replaceAll('\n', '<br>')}</p>
<hr>
''';
      }).join('\n')}
</body>
</html>
''';
    }

    return history
        .map((item) {
          return '''
${item.action.toUpperCase()} Â· ${item.provider} - pagina ${item.page}

ORIGINALE:
${item.original}

RISULTATO:
${item.result}

----------------------------------------
''';
        })
        .join('\n');
  }
}
