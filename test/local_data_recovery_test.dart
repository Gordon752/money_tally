import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/export/export_file_service.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/local_data_recovery_service.dart';
import 'package:money_tally/src/persistence/firestore_record_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final raw in ['{broken json', '[1,2]', '{"accounts":42}', '{}']) {
    testWidgets('unreadable local data offers validated restore: $raw', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'money_tally_finance_data_set_v2': raw,
      });
      PackageInfo.setMockInitialValues(
        appName: 'Trackmark Money',
        packageName: 'test',
        version: '1.0',
        buildNumber: '1',
        buildSignature: 'test',
      );
      await expectLater(
        const LocalFinanceDataSetRepository().load(),
        throwsA(anything),
      );
      await tester.pumpWidget(const MoneyTallyBootstrap());
      await tester.pumpAndSettle();
      expect(find.text('Trackmark Money could not start'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'money_tally_finance_data_set_v2',
        ),
        raw,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Choose Backup'),
        findsOneWidget,
      );
    });
  }
  for (final source in ['On My iPhone', 'iCloud Drive']) {
    testWidgets(
      '$source backup is validated, previewed and confirmed through existing picker',
      (tester) async {
        SharedPreferences.setMockInitialValues({'recovery-ui': '{bad'});
        final service = _UiRecoveryService();
        final fixture = FinanceDataStore.empty();
        final valid = const BackupCodec().encodeJson(fixture.dataSet);
        fixture.dispose();
        var selected = 'invalid JSON';
        var targetReads = 0;
        var startupRetries = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: LocalDataRecoveryView(
              failure: service.failure,
              recoveryService: service,
              onRetry: () => startupRetries++,
              loadCloudTarget: () async {
                targetReads++;
                return RecoveryCloudTarget(
                  repository: FirestoreRecordRepository(
                    firestore: TestFirestore(),
                  ),
                  userId: 'signed-in-user',
                );
              },
              importFileService: BackupImportFileService(
                picker: () async => XFile.fromData(
                  utf8.encode(selected),
                  name: 'backup.json',
                  path: '/$source/backup.json',
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Choose Backup'));
        await tester.pumpAndSettle();
        expect(find.textContaining('not valid JSON'), findsOneWidget);
        expect(targetReads, 0);
        expect(service.restores, 0);
        selected = valid;
        await tester.tap(find.text('Choose Backup'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Restore Backup?'), findsOneWidget);
        expect(
          find.textContaining('authoritative Trackmark cloud dataset'),
          findsOneWidget,
        );
        expect(service.restores, 0);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          (await SharedPreferences.getInstance()).getString('recovery-ui'),
          '{bad',
        );
        await tester.tap(find.text('Choose Backup'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.widgetWithText(FilledButton, 'Restore Backup'));
        await tester.pumpAndSettle();
        expect(service.restores, 1);
        expect(service.restoredJson, valid);
        await tester.tap(find.text('Open Trackmark'));
        expect(startupRetries, 1);
      },
    );
  }

  for (final width in [320.0, 834.0, 1120.0]) {
    testWidgets('recovery remains readable at width $width with large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 700),
              textScaler: TextScaler.linear(2),
            ),
            child: LocalDataRecoveryView(
              failure: _UiRecoveryService().failure,
              onRetry: () => retries++,
              loadCloudTarget: () async => const RecoveryCloudTarget(),
              importFileService: BackupImportFileService(
                picker: () async => null,
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Choose Backup'));
      await tester.tap(find.text('Choose Backup'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retry Startup'));
      await tester.tap(find.text('Retry Startup'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

class _UiRecoveryService extends LocalDataRecoveryService {
  _UiRecoveryService()
    : super(
        failure: const UnreadableLocalFinanceData(
          storageKey: 'recovery-ui',
          original: '{bad',
        ),
      );
  int restores = 0;
  String? restoredJson;
  @override
  Future<LocalDataRecoveryResult> restore({
    required String backupJson,
    required RecoveryCloudTarget target,
  }) async {
    validator.validate(backupJson);
    restores++;
    restoredJson = backupJson;
    return const LocalDataRecoveryResult(
      originalPath: '/test/original.txt',
      sourceBackupPath: '/test/source.json',
    );
  }
}
