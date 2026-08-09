import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/export/export_file_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test(
    'export file service writes and shares a MIME-aware temporary file',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'money_tally_export_service_test_',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));

      ShareParams? capturedParams;
      final service = ExportFileService(
        temporaryDirectoryProvider: () async => temporaryDirectory,
        shareLauncher: (params) async {
          capturedParams = params;
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      );
      const origin = Rect.fromLTWH(20, 40, 320, 68);

      final exported = await service.shareTextFile(
        content: 'transaction_id,amount\nexpense-1,12.50',
        fileName: 'money_tally_transactions_2026-07-23.csv',
        mimeType: 'text/csv',
        shareTitle: 'Trackmark Money transactions',
        sharePositionOrigin: origin,
      );

      expect(exported.fileName, 'money_tally_transactions_2026-07-23.csv');
      expect(exported.mimeType, 'text/csv');
      expect(await File(exported.path).readAsString(), contains('expense-1'));
      expect(capturedParams, isNotNull);
      expect(capturedParams!.files, hasLength(1));
      expect(capturedParams!.files!.single.path, exported.path);
      expect(capturedParams!.files!.single.mimeType, 'text/csv');
      expect(capturedParams!.fileNameOverrides, [exported.fileName]);
      expect(capturedParams!.sharePositionOrigin, origin);
    },
  );

  test('export filenames use safe date and local-time components', () {
    final createdAt = DateTime(2026, 7, 23, 22, 45);

    expect(
      csvExportFileName(createdAt),
      'money_tally_transactions_2026-07-23.csv',
    );
    expect(
      backupExportFileName(createdAt),
      'money_tally_backup_2026-07-23_2245.json',
    );
  });

  test('native backup selection preserves the chosen JSON exactly', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trackmark_native_backup_import_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/Trackmark Backup.json');
    const content = '{\n  "schemaVersion": 4,\n  "exact": "spacing"\n}\n';
    await file.writeAsString(content);
    final service = BackupImportFileService(
      picker: () async => XFile(file.path, mimeType: 'application/json'),
    );

    final imported = await service.selectBackup();

    expect(imported, isNotNull);
    expect(imported!.name, 'Trackmark Backup.json');
    expect(imported.path, file.path);
    expect(imported.content, content);
  });

  test(
    'an automatic safety backup can be shared to external storage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trackmark_share_safety_backup_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/Trackmark Pre-Restore Backup.json');
      await file.writeAsString('{"schemaVersion":4}');
      ShareParams? captured;
      final service = ExportFileService(
        shareLauncher: (params) async {
          captured = params;
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      );

      await service.shareExistingFile(
        file: ExportedFile(
          path: file.path,
          fileName: file.uri.pathSegments.last,
          mimeType: 'application/json',
        ),
        shareTitle: 'Trackmark pre-restore safety backup',
        sharePositionOrigin: const Rect.fromLTWH(10, 10, 20, 20),
      );

      expect(captured, isNotNull);
      expect(captured!.files!.single.path, file.path);
      expect(captured!.fileNameOverrides, [file.uri.pathSegments.last]);
    },
  );
}
