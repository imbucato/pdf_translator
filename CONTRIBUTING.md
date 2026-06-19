# Contributing to AI Reader

Thanks for your interest in contributing to **AI Reader**.

This is a personal Flutter Android reader project focused on PDF/EPUB reading, bookmarks, notes, reading comfort and practical AI-assisted reading.

Small, careful improvements are very welcome.

---

## How to contribute

The preferred workflow is:

1. Fork the repository.
2. Create a feature branch.
3. Make a small, focused change.
4. Run:

```bash
flutter analyze
```

5. Open a pull request.
6. Describe clearly what changed and why.

Please do not push unrelated changes in the same pull request.

---

## Good contributions

Good contribution ideas include:

* bug fixes
* UI polish
* better error messages
* Android compatibility fixes
* small EPUB reading comfort improvements
* small PDF reader improvements
* bookmark and note usability improvements
* storage reliability improvements
* documentation improvements
* small performance improvements

---

## Please avoid

Please avoid these unless discussed first:

* large refactors
* replacing the EPUB lazy rendering system
* switching the EPUB reader back to `SingleChildScrollView + Column`
* using `GlobalKey + ensureVisible` for chapters that may not be built yet
* adding text-to-speech / read aloud features
* adding a full dark theme
* adding a heavy library management system
* adding study-oriented features such as flashcards
* adding new dependencies without a strong reason
* changing PDF thumbnail/cache behavior unless strictly necessary
* touching unrelated files just for formatting

---

## EPUB performance rules

The EPUB reader must stay lazy and performant.

Do not render all chapters at once.

Avoid approaches that build the entire book into a single huge widget tree.

Large EPUB files must remain usable on older Android devices.

---

## PDF performance rules

PDF performance should be checked with a release APK.

Debug mode may be much slower and is not a reliable performance benchmark.

When changing PDF-related code, avoid unnecessary rebuilds of the PDF viewer.

---

## Imported documents

AI Reader imports PDF/EPUB files selected through the file picker into an internal persistent app folder.

This is intentional.

Do not change the app back to depending on temporary `file_picker` cache paths.

Internal paths are used for:

* recent documents
* pinned documents
* reading progress
* bookmarks
* bookmark notes
* imported document archive

The app must never delete the user's original external file.

When deleting from the imported documents archive, only delete files inside the app's internal imported documents directory.

---

## Bookmarks and notes

Bookmarks may include:

* document path
* document type
* PDF page number
* EPUB chapter index
* EPUB book/chapter progress
* optional note

Changes to bookmark storage must remain backward compatible with older saved data.

Old bookmarks without newer fields must not crash the app.

---

## AI-related behavior

Do not commit API keys, secrets, local credentials or private configuration.

AI features should remain optional and practical for reading support.

---

## Before submitting a pull request

Please check:

```bash
flutter analyze
```

Also verify, when relevant:

* PDF still opens.
* EPUB still opens.
* recent documents still work.
* reading progress is restored.
* bookmarks still work.
* bookmark notes still work.
* EPUB selection and AI panel still work.
* imported documents archive still works.

---

## Commit style

Use clear commit messages, for example:

```text
Fix EPUB bookmark label
Improve imported documents UI
Add missing-file handling
Clean PDF display titles
```

---

## Pull request description

Please include:

* what changed
* why it changed
* how it was tested
* screenshots if the change affects UI
* any known limitations

---

## Project direction

AI Reader should remain:

* lightweight
* practical
* comfortable for reading
* Android-focused
* careful with performance
* easy to maintain

When in doubt, prefer a small improvement over a large redesign.
