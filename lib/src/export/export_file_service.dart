import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef ExportTemporaryDirectoryProvider = Future<Directory> Function();
typedef ExportShareLauncher = Future<ShareResult> Function(ShareParams params);

class ExportedFile {
  const ExportedFile({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  final String path;
  final String fileName;
  final String mimeType;
}

class ExportFileService {
  ExportFileService({
    ExportTemporaryDirectoryProvider? temporaryDirectoryProvider,
    ExportShareLauncher? shareLauncher,
  }) : _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _shareLauncher = shareLauncher ?? SharePlus.instance.share;

  final ExportTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final ExportShareLauncher _shareLauncher;

  Future<ExportedFile> shareTextFile({
    required String content,
    required String fileName,
    required String mimeType,
    required String shareTitle,
    required Rect sharePositionOrigin,
  }) async {
    if (fileName.isEmpty ||
        fileName.contains('/') ||
        fileName.contains(Platform.pathSeparator)) {
      throw ArgumentError.value(fileName, 'fileName', 'Invalid file name');
    }

    final temporaryDirectory = await _temporaryDirectoryProvider();
    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsString(content, encoding: utf8, flush: true);

    await _shareLauncher(
      ShareParams(
        title: shareTitle,
        files: [XFile(file.path, mimeType: mimeType)],
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );

    return ExportedFile(
      path: file.path,
      fileName: fileName,
      mimeType: mimeType,
    );
  }
}

String csvExportFileName(DateTime createdAt) {
  return 'money_tally_transactions_${_fileDate(createdAt)}.csv';
}

String backupExportFileName(DateTime createdAt) {
  final hour = createdAt.hour.toString().padLeft(2, '0');
  final minute = createdAt.minute.toString().padLeft(2, '0');
  return 'money_tally_backup_${_fileDate(createdAt)}_$hour$minute.json';
}

String _fileDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
