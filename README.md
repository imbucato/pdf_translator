# AI Reader

**AI Reader** is a Flutter Android app for reading PDF and EPUB documents, keeping reading progress, managing bookmarks and notes, and using AI actions on selected text.

The project started as a personal reader focused on comfort, lightweight reading tools, and practical AI-assisted reading.

> Current target: Android
> Framework: Flutter / Dart

---

## Features

### PDF and EPUB reading

* Open PDF and EPUB files from the device.
* Imported documents are copied into a persistent internal app archive.
* Recent documents and reading progress use stable internal paths instead of temporary `file_picker` cache paths.
* Existing cache-based records are migrated when reopened.
* If a document is missing, the app shows a friendly message instead of crashing.

### Reading progress

* Continue reading from the last position.
* Recent documents view.
* Pinned documents.
* "Continue reading" card on the Home page.

### Bookmarks

* Multiple bookmarks per PDF.
* Multiple bookmarks per EPUB, including multiple bookmarks in the same chapter.
* Bookmarks are available both from the Home page and directly inside the reader.
* EPUB bookmarks show:

  * real chapter title
  * book progress percentage
  * chapter progress percentage
* PDF bookmarks show page information.
* Optional text notes can be added to bookmarks.

### Bookmark notes

* Each bookmark can have an optional personal note.
* Notes are edited in a dedicated page to avoid keyboard/dialog layout issues.
* Notes are persisted and remain attached to the bookmark.
* Bookmark note editor has a polished UI.

### EPUB comfort settings

* Reading presets.
* Font size, spacing and layout options.
* Text alignment options.
* Multiple system font choices, including:

  * Default
  * Sans
  * Serif
  * Monospace
  * Condensed
  * Light
  * Arial
  * Times
  * Comic
  * Cursive
  * Thin
  * Serif Mono
* Page background colors:

  * White
  * Paper
  * Cream
  * Soft gray

### Imported documents archive

* View documents imported into the app's internal archive.
* See file type and file size.
* See total storage used.
* Open imported documents.
* Delete internal copies safely.
* Deleting an internal copy can also remove related internal references such as:

  * recent document
  * pinned document
  * reading progress
  * bookmarks
  * bookmark notes

The app never deletes the original external file selected by the user.

### AI-assisted reading

* Select text and use AI actions.
* Designed for reading support, translation and comprehension workflows.

---

## Project philosophy

AI Reader is meant to stay practical and lightweight.

The project is **not** currently focused on:

* full dark theme
* text-to-speech / read aloud
* heavy library management
* study-oriented flashcards
* large refactors that risk reading performance

The goal is a pleasant reader for personal reading, with useful AI support and a clean Android experience.

---

## Technical notes

### EPUB rendering

The EPUB reader uses lazy rendering. Avoid replacing it with a full `SingleChildScrollView + Column` containing all chapters, because that causes serious performance problems on large EPUB files.

Do not use `GlobalKey + ensureVisible` for chapters that may not be built yet.

### PDF performance

PDF performance should be tested with a release APK, especially on older Android tablets.

Debug mode is not representative for real PDF performance.

### Imported documents

Documents selected through file picker may originally come from a temporary cache path such as:

```text
/data/user/0/com.example.pdf_translator/cache/file_picker/...
```

AI Reader imports them into a persistent app directory such as:

```text
/data/user/0/com.example.pdf_translator/app_flutter/ai_reader_documents/...
```

This makes recent documents, bookmarks, notes and progress more reliable.

---

## Getting started

### Requirements

* Flutter SDK
* Android SDK
* Android device or emulator
* VS Code or Android Studio

Check your Flutter setup:

```bash
flutter doctor
```

Install dependencies:

```bash
flutter pub get
```

Analyze the project:

```bash
flutter analyze
```

Run in debug mode:

```bash
flutter run
```

Build release APK:

```bash
flutter build apk --release
```

Install release APK on a connected Android device:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" uninstall com.example.pdf_translator
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install build\app\outputs\flutter-apk\app-release.apk
```

---

## Repository structure

Typical project areas:

```text
lib/
  models/
  pages/
  services/
  widgets/
```

Important areas include:

* reader pages for PDF and EPUB
* storage service
* bookmark model
* imported document management
* EPUB reading preferences

---

## Contributing

Contributions are welcome, especially small and focused improvements.

Before opening a pull request, please read [`CONTRIBUTING.md`](CONTRIBUTING.md).

Good contribution areas:

* UI polish
* bug fixes
* Android compatibility
* EPUB reading comfort
* storage reliability
* documentation
* small performance improvements

Please avoid large refactors unless discussed first.

---

## License

This project is released under the MIT License. See [`LICENSE`](LICENSE).
