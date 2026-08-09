import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../persistence/backup_restore_service.dart';

typedef ExportTemporaryDirectoryProvider = Future<Directory> Function();
typedef ExportShareLauncher = Future<ShareResult> Function(ShareParams params);
typedef BackupFilePicker = Future<XFile?> Function();
typedef BackupDirectoryProvider = Future<Directory> Function();

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

  Future<void> shareExistingFile({
    required ExportedFile file,
    required String shareTitle,
    required Rect sharePositionOrigin,
  }) async {
    await _shareLauncher(
      ShareParams(
        title: shareTitle,
        files: [XFile(file.path, mimeType: file.mimeType)],
        fileNameOverrides: [file.fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}

class ImportedBackupFile {
  const ImportedBackupFile({
    required this.name,
    required this.path,
    required this.content,
  });

  final String name;
  final String path;
  final String content;
}

class BackupImportFileService {
  BackupImportFileService({BackupFilePicker? picker})
    : _picker = picker ?? _pickJsonFile;

  final BackupFilePicker _picker;

  Future<ImportedBackupFile?> selectBackup() async {
    final selected = await _picker();
    if (selected == null) return null;
    return ImportedBackupFile(
      name: selected.name,
      path: selected.path,
      content: await selected.readAsString(),
    );
  }

  static Future<XFile?> _pickJsonFile() {
    return openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Trackmark JSON backup',
          extensions: ['json'],
          mimeTypes: ['application/json', 'text/json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
  }
}

class BackupSafetyFileService {
  BackupSafetyFileService({
    BackupDirectoryProvider? directoryProvider,
    this._validator = const BackupRestoreValidator(),
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory;

  final BackupDirectoryProvider _directoryProvider;
  final BackupRestoreValidator _validator;

  Future<ExportedFile> savePreRestoreBackup({
    required String content,
    required DateTime createdAt,
  }) async {
    _validator.validate(content);
    final root = await _directoryProvider();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}Trackmark Backups',
    );
    await directory.create(recursive: true);
    final fileName = preRestoreBackupFileName(createdAt);
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(content, encoding: utf8, flush: true);
    final verified = await file.readAsString(encoding: utf8);
    if (verified != content) {
      throw const FileSystemException('Safety backup verification failed');
    }
    _validator.validate(verified);
    return ExportedFile(
      path: file.path,
      fileName: fileName,
      mimeType: 'application/json',
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

String preRestoreBackupFileName(DateTime createdAt) {
  final hour = createdAt.hour.toString().padLeft(2, '0');
  final minute = createdAt.minute.toString().padLeft(2, '0');
  final second = createdAt.second.toString().padLeft(2, '0');
  return 'Trackmark Pre-Restore Backup - ${_fileDate(createdAt)} '
      '$hour$minute$second.json';
}

String _fileDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
