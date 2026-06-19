import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DocumentImportService {
  static const String documentsFolderName = 'ai_reader_documents';

  Future<Directory> persistentDocumentsDirectory() async {
    return _persistentDocumentsDirectory();
  }

  Future<List<File>> importedDocuments() async {
    final documentsDirectory = await _persistentDocumentsDirectory();
    final files =
        documentsDirectory.listSync().whereType<File>().where((file) {
          final extension = _extensionFromPath(file.path);

          return extension == 'pdf' || extension == 'epub';
        }).toList()..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );

    if (kDebugMode) {
      final totalBytes = files.fold<int>(
        0,
        (total, file) => total + file.lengthSync(),
      );
      debugPrint(
        '[AI_READER_IMPORTED_DOCS] count=${files.length} totalBytes=$totalBytes '
        'directory="${documentsDirectory.path}"',
      );
    }

    return files;
  }

  Future<bool> deleteImportedDocument(String path) async {
    if (!await isInPersistentDocuments(path)) return false;

    final file = File(path);
    if (!file.existsSync()) return false;

    await file.delete();

    if (kDebugMode) {
      debugPrint('[AI_READER_IMPORTED_DOC_DELETE] path="$path" deleted=true');
    }

    return true;
  }

  Future<File> importDocument(String sourcePath) async {
    final sourceFile = File(sourcePath);

    if (_isInPersistentDocuments(sourcePath)) {
      _debugLogImport(sourcePath, sourcePath, alreadyPersistent: true);
      return sourceFile;
    }

    final sourceExists = sourceFile.existsSync();
    if (!sourceExists) {
      _debugLogImport(sourcePath, sourcePath, sourceExists: false);
      return sourceFile;
    }

    final documentsDirectory = await _persistentDocumentsDirectory();
    final destinationPath = await _uniqueDestinationPath(
      documentsDirectory,
      _fileNameFromPath(sourcePath),
    );
    final importedFile = await sourceFile.copy(destinationPath);

    _debugLogImport(sourcePath, importedFile.path);

    return importedFile;
  }

  Future<bool> isInPersistentDocuments(String path) async {
    final documentsDirectory = await _persistentDocumentsDirectory();
    final normalizedPath = _normalize(path);
    final normalizedRoot = _normalize(documentsDirectory.path);

    return normalizedPath == normalizedRoot ||
        normalizedPath.startsWith('$normalizedRoot/');
  }

  bool looksTemporary(String path) {
    final normalizedPath = _normalize(path).toLowerCase();

    return normalizedPath.contains('/cache/') ||
        normalizedPath.contains('file_picker') ||
        normalizedPath.contains('/data/user/0/');
  }

  bool _isInPersistentDocuments(String path) {
    final normalizedPath = _normalize(path);

    return normalizedPath.contains('/$documentsFolderName/');
  }

  Future<Directory> _persistentDocumentsDirectory() async {
    final appDocumentsDirectory = await getApplicationDocumentsDirectory();
    final documentsDirectory = Directory(
      '${appDocumentsDirectory.path}${Platform.pathSeparator}$documentsFolderName',
    );

    if (!documentsDirectory.existsSync()) {
      await documentsDirectory.create(recursive: true);
    }

    return documentsDirectory;
  }

  Future<String> _uniqueDestinationPath(
    Directory directory,
    String fileName,
  ) async {
    final cleanedFileName = _cleanFileName(fileName);
    final dotIndex = cleanedFileName.lastIndexOf('.');
    final baseName = dotIndex > 0
        ? cleanedFileName.substring(0, dotIndex)
        : cleanedFileName;
    final extension = dotIndex > 0 ? cleanedFileName.substring(dotIndex) : '';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    var candidate =
        '${directory.path}${Platform.pathSeparator}${baseName}_$timestamp$extension';
    var counter = 1;

    while (File(candidate).existsSync()) {
      candidate =
          '${directory.path}${Platform.pathSeparator}${baseName}_${timestamp}_$counter$extension';
      counter++;
    }

    return candidate;
  }

  String _fileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));

    return parts.isEmpty ? 'document' : parts.last;
  }

  String _extensionFromPath(String path) {
    final fileName = _fileNameFromPath(path);
    final dotIndex = fileName.lastIndexOf('.');

    return dotIndex < 0 ? '' : fileName.substring(dotIndex + 1).toLowerCase();
  }

  String _cleanFileName(String fileName) {
    final cleaned = fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned.isEmpty ? 'document' : cleaned;
  }

  String _normalize(String path) {
    return path.replaceAll('\\', '/');
  }

  void _debugLogImport(
    String sourcePath,
    String destinationPath, {
    bool sourceExists = true,
    bool alreadyPersistent = false,
  }) {
    if (!kDebugMode) return;

    final normalizedSource = _normalize(sourcePath).toLowerCase();

    debugPrint(
      '[AI_READER_DOC_IMPORT] source="$sourcePath" '
      'destination="$destinationPath" '
      'sourceExists=$sourceExists '
      'destinationExists=${File(destinationPath).existsSync()} '
      'alreadyPersistent=$alreadyPersistent '
      'cache=${normalizedSource.contains('/cache/')} '
      'filePicker=${normalizedSource.contains('file_picker')} '
      'dataUser0=${normalizedSource.contains('/data/user/0/')}',
    );
  }
}
