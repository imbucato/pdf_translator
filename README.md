# pdf_translator

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

Cosa contiene ogni file:

lib/main.dart (line 1)

avvio Flutter
caricamento .env
MaterialApp
lib/models/history_item.dart (line 1)

modello HistoryItem
conversione JSON
lib/services/ai_service.dart (line 1)

AiProvider
prompt
chiamate OpenAI / DeepSeek
lettura API key da dotenv
lib/services/storage_service.dart (line 1)

SharedPreferences
provider salvato
auto traduzione
ultima pagina PDF
cronologia
cache
lib/services/export_service.dart (line 1)

export TXT / Markdown / HTML
lib/pages/pdf_translator_page.dart (line 1)

UI principale
PDF viewer
bottoni
stato pagina
dialog/bottom sheet