import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/backup_storage.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('available iCloud selection updates the persisted preference', (
    tester,
  ) async {
    final store = _store();
    await _pumpSettings(
      tester,
      store: store,
      iCloud: _AvailabilityStorage(BackupStorageState.available),
    );

    final location = find.byKey(const ValueKey('automatic-backup-location'));
    await tester.ensureVisible(location);
    await tester.tap(location);
    await tester.pumpAndSettle();
    await tester.tap(find.text('iCloud Drive').last);
    await tester.pumpAndSettle();

    expect(
      store.preferences.automaticBackupLocation,
      AutomaticBackupLocation.iCloud,
    );
    expect(find.text('iCloud Drive'), findsOneWidget);
  });

  testWidgets('unavailable iCloud leaves the existing location unchanged', (
    tester,
  ) async {
    final store = _store();
    await _pumpSettings(
      tester,
      store: store,
      iCloud: _AvailabilityStorage(BackupStorageState.unavailable),
    );

    final location = find.byKey(const ValueKey('automatic-backup-location'));
    await tester.ensureVisible(location);
    await tester.tap(location);
    await tester.pumpAndSettle();
    await tester.tap(find.text('iCloud Drive').last);
    await tester.pumpAndSettle();

    expect(find.text('iCloud Drive is unavailable'), findsOneWidget);
    expect(
      store.preferences.automaticBackupLocation,
      AutomaticBackupLocation.local,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('On My Device'), findsOneWidget);
  });
}

FinanceDataStore _store() => FinanceDataStore(
  dataSet: const FinanceDataSet(
    accounts: [],
    categories: [],
    transactions: [],
    scheduledTransactions: [],
    budgets: [],
    preferences: UserPreferences(automaticBackupsEnabled: true),
  ),
);

Future<void> _pumpSettings(
  WidgetTester tester, {
  required FinanceDataStore store,
  required BackupStorage iCloud,
}) => tester.pumpWidget(
  MaterialApp(
    home: FinanceDataStoreScope(
      store: store,
      child: Scaffold(
        body: SingleChildScrollView(
          child: SettingsView(iCloudBackupStorage: iCloud),
        ),
      ),
    ),
  ),
);

class _AvailabilityStorage implements BackupStorage {
  _AvailabilityStorage(this.state);

  final BackupStorageState state;

  @override
  Future<BackupStorageStatus> status() async =>
      BackupStorageStatus(state: state);

  @override
  Future<BackupStorageEntry> write({
    required String content,
    required String fileName,
  }) => throw UnimplementedError();

  @override
  Future<String> read(String fileName) => throw UnimplementedError();

  @override
  Future<List<BackupStorageEntry>> list() => throw UnimplementedError();

  @override
  Future<void> delete(String fileName) => throw UnimplementedError();

  @override
  Future<BackupStorageStatus> downloadIfNeeded(String fileName) =>
      throw UnimplementedError();

  @override
  Future<BackupStorageStatus> entryStatus(String fileName) =>
      throw UnimplementedError();

  @override
  Future<void> prune({
    required bool Function(String fileName) matches,
    required int retain,
  }) => throw UnimplementedError();
}
