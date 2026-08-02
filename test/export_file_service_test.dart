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
}
