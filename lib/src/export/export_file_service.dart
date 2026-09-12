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

  Future<Directory> backupDirectory() async {
    final root = await _directoryProvider();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}Trackmark Backups',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<ExportedFile> savePreRestoreBackup({
    required String content,
    required DateTime createdAt,
  }) async {
    return saveVerifiedBackup(
      content: content,
      fileName: preRestoreBackupFileName(createdAt),
    );
  }

  Future<ExportedFile> savePreResetBackup({
    required String content,
    required DateTime createdAt,
  }) async {
    return saveVerifiedBackup(
      content: content,
      fileName: preResetBackupFileName(createdAt),
    );
  }

  Future<ExportedFile> saveVerifiedBackup({
    required String content,
    required String fileName,
  }) async {
    _validator.validate(content);
    final directory = await backupDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    final pending = File('${file.path}.pending');
    await pending.writeAsString(content, encoding: utf8, flush: true);
    try {
      final verified = await pending.readAsString(encoding: utf8);
      if (verified != content) {
        throw const FileSystemException('Safety backup verification failed');
      }
      _validator.validate(verified);
      await pending.rename(file.path);
    } on Object {
      if (await pending.exists()) await pending.delete();
      rethrow;
    }
    return ExportedFile(
      path: file.path,
      fileName: fileName,
      mimeType: 'application/json',
    );
  }

  Future<void> verifyExistingBackup(File file) async {
    final content = await file.readAsString(encoding: utf8);
    _validator.validate(content);
  }

  Future<void> prune({
    required bool Function(String fileName) matches,
    required int retain,
  }) async {
    final directory = await backupDirectory();
    final files = await directory
        .list()
        .where((entry) => entry is File && matches(_baseName(entry.path)))
        .cast<File>()
        .toList();
    final datedFiles = <({File file, DateTime modifiedAt})>[];
    for (final file in files) {
      datedFiles.add((file: file, modifiedAt: await file.lastModified()));
    }
    datedFiles.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    for (final entry in datedFiles.skip(retain)) {
      await entry.file.delete();
    }
  }
}

String csvExportFileName(DateTime createdAt) {
  return 'money_tally_transactions_${_fileDate(createdAt)}.csv';
}

String backupExportFileName(DateTime createdAt) {
  return 'trackmark_money_backup_${_fileTimestamp(createdAt)}.json';
}

String preRestoreBackupFileName(DateTime createdAt) {
  return 'trackmark_money_pre_restore_backup_${_fileTimestamp(createdAt)}.json';
}

String preResetBackupFileName(DateTime createdAt) {
  return 'trackmark_money_pre_reset_backup_${_fileTimestamp(createdAt)}.json';
}

String automaticBackupFileName(DateTime createdAt) {
  return 'trackmark_money_automatic_backup_${_fileTimestamp(createdAt)}.json';
}

String preUpdateBackupFileName({
  required String oldVersion,
  required String newVersion,
  required DateTime createdAt,
}) {
  return 'trackmark_money_pre_update_backup_'
      '${_safeFileComponent(oldVersion)}_to_${_safeFileComponent(newVersion)}_'
      '${_fileTimestamp(createdAt)}.json';
}

bool isTrackmarkAutomaticBackupFileName(String fileName) => RegExp(
  r'^trackmark_money_automatic_backup_\d{4}-\d{2}-\d{2}_\d{6}\.json$',
).hasMatch(fileName);

bool isTrackmarkPreUpdateBackupFileName(String fileName) => RegExp(
  r'^trackmark_money_pre_update_backup_.+_to_.+_\d{4}-\d{2}-\d{2}_\d{6}\.json$',
).hasMatch(fileName);

String _fileTimestamp(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  final second = date.second.toString().padLeft(2, '0');
  return '${_fileDate(date)}_$hour$minute$second';
}

String _safeFileComponent(String value) => value
    .trim()
    .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
    .replaceAll(RegExp(r'_+'), '_');

String _baseName(String path) => path.split(Platform.pathSeparator).last;

String _fileDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
