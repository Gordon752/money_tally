import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/design/accent_color_catalog.dart';
import 'package:money_tally/src/design/app_icons.dart';
import 'package:money_tally/src/design/credit_card_appearance.dart';
import 'package:money_tally/src/design/design_tokens.dart';
import 'package:money_tally/src/design/widgets/amount_entry_field.dart';
import 'package:money_tally/src/design/widgets/account_balance_text.dart';
import 'package:money_tally/src/design/widgets/account_card.dart';
import 'package:money_tally/src/design/widgets/category_icon_badge.dart';
import 'package:money_tally/src/design/widgets/percentage_entry_field.dart';
import 'package:money_tally/src/design/widgets/trackmark_switch.dart';
import 'package:money_tally/src/design/money_format.dart';
import 'package:money_tally/src/domain/account.dart' as v2_account;
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart' as v2_category;
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart'
    as v2_scheduled;
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/transaction.dart' as v2_transaction;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/export/export_file_service.dart';
import 'package:money_tally/src/migration/v1_snapshot_migrator.dart';
import 'package:money_tally/src/notifications/notification_scheduler.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_restore_service.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder ledgerRowWithText(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == 'LedgerJournalRow',
  ),
);

v2_account.AccountRecord _creditInsightsWidgetAccount({
  required DateTime createdAt,
  required int statementClosingDay,
}) {
  return v2_account.AccountRecord(
    id: 'credit-insights-completeness',
    name: 'Credit Card',
    type: v2_account.AccountType.creditCard,
    openingBalanceMinor: -100000,
    creditLimitMinor: 200000,
    interestEstimationEnabled: true,
    annualPercentageRate: 24,
    statementClosingDay: statementClosingDay,
    paymentDueDay: 28,
    sync: v2_sync.SyncMetadata.fresh(now: createdAt, deviceId: 'test'),
  );
}

Future<void> collapseScheduledCalendar(WidgetTester tester) async {
  final collapse = find.byTooltip('Collapse calendar');
  if (collapse.evaluate().isEmpty) return;
  await tester.tap(collapse);
  await tester.pumpAndSettle();
}

typedef RecordedExportShare = ({
  String content,
  String fileName,
  String mimeType,
  String shareTitle,
  Rect sharePositionOrigin,
});

class RecordingExportFileService extends ExportFileService {
  RecordingExportFileService({this.holdFirstShare = false, this.failure});

  final bool holdFirstShare;
  final Object? failure;
  final recordedShares = <RecordedExportShare>[];
  final firstShare = Completer<ExportedFile>();

  @override
  Future<ExportedFile> shareTextFile({
    required String content,
    required String fileName,
    required String mimeType,
    required String shareTitle,
    required Rect sharePositionOrigin,
  }) {
    final error = failure;
    if (error != null) return Future.error(error);
    recordedShares.add((
      content: content,
      fileName: fileName,
      mimeType: mimeType,
      shareTitle: shareTitle,
      sharePositionOrigin: sharePositionOrigin,
    ));
    if (holdFirstShare && recordedShares.length == 1) {
      return firstShare.future;
    }
    return Future.value(
      ExportedFile(
        path: '/temporary/$fileName',
        fileName: fileName,
        mimeType: mimeType,
      ),
    );
  }
}

class RecordingBackupSafetyFileService extends BackupSafetyFileService {
  String? savedContent;
  DateTime? savedAt;

  @override
  Future<ExportedFile> savePreResetBackup({
    required String content,
    required DateTime createdAt,
  }) async {
    const BackupRestoreValidator().validate(content);
    savedContent = content;
    savedAt = createdAt;
    return ExportedFile(
      path: '/temporary/${preResetBackupFileName(createdAt)}',
      fileName: preResetBackupFileName(createdAt),
      mimeType: 'application/json',
    );
  }
}

class TestNotificationScheduler implements NotificationScheduler {
  final scheduledIds = <String>[];
  final cancelledIds = <String>[];
  final badgeCounts = <int>[];

  @override
  Future<void> cancelScheduledTransaction(
    v2_scheduled.ScheduledTransactionRecord scheduledTransaction,
  ) async {
    cancelledIds.add(scheduledTransaction.id);
  }

  @override
  Future<bool> requestPermissionIfNeeded() async => true;

  @override
  Future<void> rescheduleScheduledTransaction(
    v2_scheduled.ScheduledTransactionRecord scheduledTransaction,
  ) async {
    scheduledIds.add(scheduledTransaction.id);
  }

  @override
  Future<List<int>> scheduleScheduledTransaction(
    v2_scheduled.ScheduledTransactionRecord scheduledTransaction,
  ) async {
    scheduledIds.add(scheduledTransaction.id);
    return const [7101];
  }

  @override
  Future<void> updateBadgeCount(int dueOrOverdueCount) async {
    badgeCounts.add(dueOrOverdueCount);
  }
}

class BlockingLocalFinanceRepository extends LocalFinanceDataSetRepository {
  BlockingLocalFinanceRepository();

  final saveCompleter = Completer<void>();
  FinanceDataSet? savedDataSet;

  @override
  Future<FinanceDataSet?> load() async => savedDataSet;

  @override
  Future<void> save(FinanceDataSet dataSet) async {
    savedDataSet = FinanceDataSet.fromJson(dataSet.toJson());
    await saveCompleter.future;
  }
}

class FailingLocalFinanceRepository extends LocalFinanceDataSetRepository {
  const FailingLocalFinanceRepository();

  @override
  Future<void> save(FinanceDataSet dataSet) {
    throw StateError('Local category save failed');
  }
}

void main() {
  test('categories and credit cards share one curated accent palette', () {
    expect(categoryColorOptions, same(TrackmarkAccentCatalog.options));
    expect(TrackmarkAccentCatalog.options.map((option) => option.label), [
      'Teal',
      'Mint',
      'Green',
      'Blue',
      'Indigo',
      'Purple',
      'Rose',
      'Red',
      'Orange',
      'Amber',
      'Gold',
      'Slate',
    ]);
    expect(
      CreditCardAppearanceCatalog.accents,
      same(TrackmarkAccentCatalog.options),
    );
    expect(
      TrackmarkAccentCatalog.options
          .where((option) => option.label == 'Teal')
          .single
          .value,
      0xFF0F766E,
    );
  });

  testWidgets('amount entry field formats typed digits as money', (
    tester,
  ) async {
    var amountMinor = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AmountEntryField(onChanged: (value) => amountMinor = value),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '500');
    await tester.pump();
    expect(amountMinor, 500);
    expect(find.text(r'$5.00'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    expect(amountMinor, 12345);
    expect(find.text(r'$123.45'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1000000');
    await tester.pump();
    expect(amountMinor, 1000000);
    expect(find.text(r'$10,000.00'), findsOneWidget);
  });

  testWidgets('percentage entry shifts digits and keeps percent visual only', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PercentageEntryField(
            controller: controller,
            focusNode: focusNode,
            onSubmitted: (_) {},
            decoration: const InputDecoration(),
          ),
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, '2');
    expect(controller.text, '0.02');
    expect(find.text('0.02'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);

    await tester.enterText(field, '28');
    expect(controller.text, '0.28');
    await tester.enterText(field, '284');
    expect(controller.text, '2.84');
    await tester.enterText(field, '2849');
    expect(controller.text, '28.49');

    await tester.enterText(field, '-700');
    expect(controller.text, '7.00');
    expect(controller.text, isNot(contains('%')));
  });

  testWidgets('amount entry field supports signed calculator input', (
    tester,
  ) async {
    var amountMinor = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AmountEntryField(
            allowNegative: true,
            onChanged: (value) => amountMinor = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '-500');
    await tester.pump();

    expect(amountMinor, -500);
    expect(find.text(r'-$5.00'), findsOneWidget);
  });

  testWidgets(
    'amount entry field focuses zero as a placeholder without selecting it',
    (tester) async {
      var amountMinor = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmountEntryField(
              autofocus: true,
              replaceZeroOnFirstInput: true,
              onChanged: (value) => amountMinor = value,
            ),
          ),
        ),
      );
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.focusNode!.hasFocus, isTrue);
      expect(
        textField.controller!.selection,
        TextSelection.collapsed(offset: textField.controller!.text.length),
      );

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: r'$0.005',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();

      expect(amountMinor, 5);
      expect(textField.controller!.text, r'$0.05');
    },
  );

  testWidgets('sync pill stays compact', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SyncPill(label: 'Synced', onSignOut: () {}),
          ),
        ),
      ),
    );

    expect(find.text('Synced'), findsOneWidget);
    expect(tester.getSize(find.byType(SyncPill)).height, lessThanOrEqualTo(36));
  });

  test('finance snapshot round trips through json', () {
    final store = FinanceStore.seeded();
    store.addCategory('Fuel');
    store.addTransaction(
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 7, 6),
      payee: 'Cafe',
      amountCents: -1299,
    );

    final snapshot = FinanceSnapshot.fromJson(store.snapshot().toJson());

    expect(snapshot.accounts.length, store.accounts.length);
    expect(snapshot.categories.last.name, 'Fuel');
    expect(snapshot.categories.last.sync.version, 1);
    expect(snapshot.categories.last.sync.deviceId, 'local');
    expect(snapshot.transactions.first.payee, 'Cafe');
    expect(snapshot.transactions.first.amountCents, -1299);
    expect(snapshot.transactions.first.sync.createdAt, isA<DateTime>());
  });

  test('sync metadata updates when records are edited', () {
    final store = FinanceStore.seeded();
    final before = store.accountById('checking').sync;

    store.adjustAccountBalance('checking', 200000);

    final after = store.accountById('checking').sync;
    expect(after.createdAt, before.createdAt);
    expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
    expect(after.version, before.version + 1);
  });

  test(
    'data store soft deletes accounts from active lists and totals',
    () async {
      final legacyStore = FinanceStore.seeded();
      final dataSet = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final dataStore = FinanceDataStore(dataSet: dataSet);

      await dataStore.deleteAccount('checking');

      final deletedAccount = dataStore.accountById('checking');
      expect(deletedAccount.isArchived, isTrue);
      expect(deletedAccount.isDeleted, isTrue);
      expect(
        dataStore.activeAccountsInDisplayOrder.map((account) => account.id),
        isNot(contains('checking')),
      );
      expect(dataStore.totalAssetsMinor, 24700);
      expect(dataStore.availableCashMinor, 24700);
    },
  );

  test(
    'store can push and pull snapshots through a remote repository',
    () async {
      final local = FinanceStore.seeded();
      final remote = FakeRemoteFinanceRepository();

      await local.pushSnapshot(remoteRepository: remote, userId: 'user-1');

      final restored = FinanceStore.seeded();
      restored.addCategory('Temporary');
      final pulled = await restored.pullSnapshot(
        remoteRepository: remote,
        userId: 'user-1',
      );

      expect(pulled, isTrue);
      expect(
        restored.categories.map((category) => category.name),
        isNot(contains('Temporary')),
      );
      expect(restored.accounts.length, local.accounts.length);
    },
  );

  testWidgets('renders finance dashboard', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    expect(find.text('Trackmark Money'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('NET WORTH'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Cash Summary'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('Next Scheduled'), findsOneWidget);
    expect(find.text('Accounts Preview'), findsOneWidget);
  });

  testWidgets('uses v2 currency preference for visible money values', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            currency: CurrencyFormatSettings(
              currencyCode: 'CAD',
              symbol: r'C$',
            ),
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    expect(find.text(r'C$1,852.40'), findsWidgets);
  });

  testWidgets('provides v2 finance data store beside legacy store', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    final context = tester.element(find.byType(MaterialApp));
    final dataStore = FinanceDataStoreScope.read(context);

    expect(
      dataStore.balanceForAccount('checking'),
      legacyStore.accountById('checking').balanceCents,
    );
  });

  testWidgets('accounts screen renders v2 account cards', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();

    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Banking'), findsWidgets);
    expect(find.text('Adjust balance'), findsNothing);
  });

  testWidgets('accounts screen can collapse account groups', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();

    final checkingCard = tester.widget<AccountCard>(
      find.byWidgetPredicate(
        (widget) => widget is AccountCard && widget.account.name == 'Checking',
      ),
    );
    expect(checkingCard.subtitle, contains(' · '));
    expect(checkingCard.subtitle, isNot('Banking'));
    expect(checkingCard.balanceFontSize, 17);

    await tester.tap(find.byKey(const ValueKey('account-group-banking')));
    await tester.pumpAndSettle();

    expect(find.text('Banking'), findsWidgets);
    expect(find.text('Checking'), findsNothing);
    expect(find.byTooltip('Expand Banking'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-group-banking')));
    await tester.pumpAndSettle();

    expect(find.text('Checking'), findsOneWidget);
  });

  testWidgets('accounts group long press can reorder fixed groups', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    final cashGroup = find.byKey(const ValueKey('account-group-cash'));
    await tester.ensureVisible(cashGroup);
    await tester.pumpAndSettle();
    await tester.longPress(cashGroup);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move Up'));
    await tester.pumpAndSettle();

    expect(dataStore.preferences.accountGroupOrderNames.take(2), [
      'cash',
      'banking',
    ]);
  });

  testWidgets('accounts group long press can rename fixed group label', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    final bankingGroup = find.byKey(const ValueKey('account-group-banking'));
    await tester.ensureVisible(bankingGroup);
    await tester.pumpAndSettle();
    await tester.longPress(bankingGroup);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Everyday Money');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(dataStore.preferences.accountGroupLabelOverrides, {
      'banking': 'Everyday Money',
    });
    expect(find.text('Everyday Money'), findsWidgets);
    expect(find.byTooltip('Collapse Everyday Money'), findsOneWidget);
  });

  testWidgets('account long press can reorder account within group', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final savings = legacyStore.addAccount(
      name: 'Savings',
      type: AccountType.savings,
      balanceCents: 10000,
    );
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.accounts,
          ),
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    expect(
      dataStore.activeAccountsInDisplayOrder
          .where((account) => account.group == v2_account.AccountGroup.banking)
          .map((account) => account.id),
      ['checking', savings.id],
    );

    await tester.longPress(find.text('Savings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move Up'));
    await tester.pumpAndSettle();

    expect(
      dataStore.activeAccountsInDisplayOrder
          .where((account) => account.group == v2_account.AccountGroup.banking)
          .map((account) => account.id),
      [savings.id, 'checking'],
    );
  });

  testWidgets('ledger screen renders v2 transaction rows', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    expect(find.text('Walmart'), findsWidgets);
    expect(find.textContaining('Checking'), findsWidgets);
  });

  testWidgets('collapsed ledger month retains its compact summary', (
    tester,
  ) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    final compactSummary = find.byWidgetPredicate(
      (widget) =>
          widget.runtimeType.toString() == 'LedgerMonthlyCompactSummary',
    );
    expect(compactSummary, findsNothing);
    expect(find.text('Walmart'), findsWidgets);

    await tester.tap(find.text(monthLabel(DateTime.now())).first);
    await tester.pumpAndSettle();

    expect(compactSummary, findsOneWidget);
    expect(find.text('Walmart'), findsNothing);
    expect(
      find.descendant(of: compactSummary, matching: find.text('Income')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: compactSummary, matching: find.text('Expenses')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: compactSummary, matching: find.text('Net')),
      findsOneWidget,
    );
  });

  test('transaction date parsing preserves the recorded time', () {
    final savedAt = DateTime(2026, 8, 4, 20, 42, 17, 321, 654);

    final parsed = parseTransactionDateInput('8/12/26', savedAt);

    expect(parsed, DateTime(2026, 8, 12, 20, 42, 17, 321, 654));
    expect(parseDateInput('8/12/26', savedAt), DateTime(2026, 8, 12));
  });

  testWidgets('ledger tap opens transaction details before editing', (
    tester,
  ) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    await tester.tap(ledgerRowWithText('Walmart').first);
    await tester.pumpAndSettle();

    expect(find.text('Transaction Details'), findsOneWidget);
    expect(find.text('Walmart'), findsWidgets);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text(r'-$64.28'), findsWidgets);
    expect(find.byKey(const ValueKey('undo-scheduled-payment')), findsNothing);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Transaction'), findsOneWidget);
    expect(find.byKey(const ValueKey('transaction-payee')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transaction-schedule-toggle')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            RegExp(r'^[A-Z][a-z]+ \d{1,2}, \d{4}$').hasMatch(widget.data!),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'generated scheduled ledger payment shows confirmation and restores occurrence',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final now = DateTime.now();
      final occurrenceDate = DateTime(now.year, now.month, now.day);
      final nextDate = DateTime(now.year, now.month + 1, now.day);
      final occurrence = v2_scheduled.ScheduledOccurrenceRecord(
        scheduledDate: occurrenceDate,
        plannedAmountMinor: 10000,
        status: v2_scheduled.ScheduledOccurrenceStatus.paid,
        actualAmountMinor: 90000,
        actualPaymentDate: occurrenceDate,
        transactionId: 'generated-undo-widget',
      );
      final schedule = scheduledExpense(
        id: 'scheduled-undo-widget',
        payee: 'Undo Bill',
        amountMinor: 10000,
        nextDate: nextDate,
      ).copyWith(occurrences: [occurrence]);
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final generated = v2_transaction.TransactionRecord(
        id: 'generated-undo-widget',
        type: v2_transaction.TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: occurrenceDate,
        payee: 'Undo Bill',
        amountMinor: 90000,
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: occurrenceDate,
        scheduledPlannedAmountMinor: 10000,
        sync: v2_sync.SyncMetadata.fresh(now: occurrenceDate),
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          transactions: [...migrated.transactions, generated],
          scheduledTransactions: [schedule],
        ),
      );
      final balanceBeforeUndo = dataStore.balanceForAccount('checking');

      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.text('Ledger').last);
      await tester.pumpAndSettle();
      await tester.tap(ledgerRowWithText('Undo Bill'));
      await tester.pumpAndSettle();

      expect(find.text('Transaction Details'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('undo-scheduled-payment')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('undo-scheduled-payment')));
      await tester.pumpAndSettle();

      expect(find.text('Undo this scheduled payment?'), findsOneWidget);
      expect(find.text('Planned amount'), findsOneWidget);
      expect(find.text('Actual payment'), findsOneWidget);
      expect(find.text(r'$100.00'), findsOneWidget);
      expect(find.text(r'$900.00'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(
        dataStore.transactions
            .singleWhere((item) => item.id == generated.id)
            .isDeleted,
        isFalse,
      );
      expect(
        dataStore.scheduledTransactions.single.occurrences.single.status,
        v2_scheduled.ScheduledOccurrenceStatus.paid,
      );

      await tester.longPress(ledgerRowWithText('Undo Bill'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('undo-scheduled-transaction-option')),
        findsOneWidget,
      );
      expect(find.text('Undo Payment'), findsOneWidget);
      await tester.ensureVisible(find.text('Delete'));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('delete-scheduled-undo-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('delete-ledger-record-only-action')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(ledgerRowWithText('Undo Bill'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('undo-scheduled-payment')));
      await tester.pumpAndSettle();
      final confirm = tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm-undo-scheduled-payment')),
      );
      confirm.onPressed!();
      confirm.onPressed!();
      await tester.pumpAndSettle();

      expect(
        dataStore.transactions
            .singleWhere((item) => item.id == generated.id)
            .isDeleted,
        isTrue,
      );
      expect(
        dataStore.balanceForAccount('checking'),
        balanceBeforeUndo + 90000,
      );
      final restored = dataStore.scheduledTransactions.single;
      expect(restored.nextDate, occurrenceDate);
      expect(restored.amountMinor, 10000);
      expect(
        restored.occurrences.single.status,
        v2_scheduled.ScheduledOccurrenceStatus.pending,
      );
      expect(restored.occurrences.single.actualAmountMinor, isNull);
      expect(dataStore.scheduledPaymentUndoTarget(generated.id), isNull);
      expect(ledgerRowWithText('Undo Bill'), findsNothing);

      await tester.tap(find.text('Dashboard').last);
      await tester.pumpAndSettle();
      expect(find.text('Undo Bill'), findsWidgets);

      await tester.tap(find.text('Scheduled').last);
      await tester.pumpAndSettle();
      await collapseScheduledCalendar(tester);
      final restoredRow = find.byKey(
        ValueKey(
          'scheduled-row-${schedule.id}-${calendarDateId(occurrenceDate)}',
        ),
      );
      expect(restoredRow, findsOneWidget);
      await tester.tap(restoredRow);
      await tester.pumpAndSettle();
      expect(find.text('Mark as Paid'), findsOneWidget);
    },
  );

  test(
    'undo recalculates scheduled summary from actual and planned amounts',
    () async {
      final occurrenceDate = DateTime(2026, 8, 21);
      final occurrence = v2_scheduled.ScheduledOccurrenceRecord(
        scheduledDate: occurrenceDate,
        plannedAmountMinor: 10000,
        status: v2_scheduled.ScheduledOccurrenceStatus.paid,
        actualAmountMinor: 90000,
        actualPaymentDate: DateTime(2026, 8, 15),
        transactionId: 'generated-summary-undo',
      );
      final schedule = scheduledExpense(
        id: 'scheduled-summary-undo',
        payee: 'Summary undo',
        amountMinor: 10000,
        nextDate: DateTime(2026, 9, 21),
      ).copyWith(occurrences: [occurrence]);
      final generated = v2_transaction.TransactionRecord(
        id: 'generated-summary-undo',
        type: v2_transaction.TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: DateTime(2026, 8, 15),
        payee: 'Summary undo',
        amountMinor: 90000,
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: occurrenceDate,
        scheduledPlannedAmountMinor: 10000,
        sync: v2_sync.SyncMetadata.fresh(now: DateTime(2026, 8, 15)),
      );
      final migrated = const V1SnapshotMigrator().migrate(
        FinanceStore.seeded().snapshot().toJson(),
      );
      final store = FinanceDataStore(
        dataSet: migrated.copyWith(
          transactions: [generated],
          scheduledTransactions: [schedule],
        ),
      );

      final paidSummary = scheduledMonthSummary(
        scheduledOccurrencesForMonth(
          store.scheduledTransactions,
          DateTime(2026, 8),
        ),
        store.transactions,
      );
      expect(paidSummary.plannedAmountMinor, 10000);
      expect(paidSummary.paidAmountMinor, 90000);
      expect(paidSummary.remainingAmountMinor, 0);

      await store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1));

      final restoredSummary = scheduledMonthSummary(
        scheduledOccurrencesForMonth(
          store.scheduledTransactions,
          DateTime(2026, 8),
        ),
        store.transactions,
      );
      expect(restoredSummary.plannedAmountMinor, 10000);
      expect(restoredSummary.paidAmountMinor, 0);
      expect(restoredSummary.remainingAmountMinor, 10000);
    },
  );

  testWidgets(
    'editing a transaction can create and reopen one future schedule',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final dataStore = FinanceDataStore(
        dataSet: const V1SnapshotMigrator().migrate(
          legacyStore.snapshot().toJson(),
        ),
      );
      final original = dataStore.transactions.singleWhere(
        (transaction) => transaction.payee == 'Walmart',
      );
      final initialScheduleCount = dataStore.scheduledTransactions.length;

      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.text('Ledger').last);
      await tester.pumpAndSettle();
      await tester.tap(ledgerRowWithText('Walmart').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      final scheduleToggle = find.byKey(
        const ValueKey('transaction-schedule-toggle'),
      );
      await tester.ensureVisible(scheduleToggle);
      await tester.tap(scheduleToggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('transaction-schedule-controls')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final updated = dataStore.transactions.singleWhere(
        (transaction) => transaction.id == original.id,
      );
      expect(updated.scheduledTransactionId, isNotNull);
      expect(
        dataStore.scheduledTransactions,
        hasLength(initialScheduleCount + 1),
      );
      final schedule = dataStore.scheduledTransactions.singleWhere(
        (item) => item.id == updated.scheduledTransactionId,
      );
      expect(schedule.payee, 'Walmart');
      expect(schedule.nextDate.isAfter(DateTime.now()), isTrue);

      await tester.tap(ledgerRowWithText('Walmart').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit future schedule'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction-schedule-toggle')),
        findsNothing,
      );
      await tester.ensureVisible(find.text('Edit future schedule'));
      await tester.tap(find.text('Edit future schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Scheduled Transaction'), findsOneWidget);
      expect(
        dataStore.scheduledTransactions,
        hasLength(initialScheduleCount + 1),
      );
    },
  );

  testWidgets('ledger search filters visible transactions', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Diner');
    await tester.pumpAndSettle();

    expect(ledgerRowWithText('Diner'), findsOneWidget);
    expect(ledgerRowWithText('Walmart'), findsNothing);
    expect(ledgerRowWithText('Settlement'), findsNothing);
  });

  testWidgets(
    'running balance is optional, account-scoped, and survives search',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          preferences: migrated.preferences.copyWith(showRunningBalance: true),
        ),
      );
      final expectedBalances = <String, int>{};
      var balance = dataStore.accountById('checking').openingBalanceMinor;
      final history =
          dataStore.transactions
              .where(
                (transaction) =>
                    !transaction.isDeleted &&
                    transaction.deltaForAccount('checking') != 0,
              )
              .toList()
            ..sort((left, right) {
              final date = left.date.compareTo(right.date);
              if (date != 0) return date;
              final created = left.sync.createdAt.compareTo(
                right.sync.createdAt,
              );
              if (created != 0) return created;
              return left.id.compareTo(right.id);
            });
      for (final transaction in history) {
        balance += transaction.deltaForAccount('checking');
        expectedBalances[transaction.id] = balance;
      }

      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.text('Ledger').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('ledger-running-balance-${history.first.id}')),
        findsNothing,
      );

      await tester.tap(find.text('Accounts').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is AccountCard && widget.account.id == 'checking',
        ),
      );
      await tester.pumpAndSettle();
      final walmart = dataStore.transactions.firstWhere(
        (transaction) => transaction.payee == 'Walmart',
      );
      expect(
        find.byKey(ValueKey('ledger-running-balance-${walmart.id}')),
        findsOneWidget,
      );
      expect(expectedBalances[walmart.id], isNotNull);

      await tester.enterText(find.byType(TextField).first, 'Walmart');
      await tester.pumpAndSettle();
      expect(ledgerRowWithText('Walmart'), findsWidgets);
      expect(
        find.byKey(ValueKey('ledger-running-balance-${walmart.id}')),
        findsOneWidget,
      );
    },
  );

  testWidgets('running-balance preference lives in Settings, not filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: migrated);
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ledger-show-running-balance')),
      findsNothing,
    );
    expect(find.text('Show Running Balance'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show Running Balance'));
    await tester.tap(
      find.ancestor(
        of: find.text('Show Running Balance'),
        matching: find.byType(TrackmarkSwitchListTile),
      ),
    );
    await tester.pumpAndSettle();

    expect(dataStore.preferences.showRunningBalance, isTrue);
    expect(find.text('Ledger Display'), findsOneWidget);
  });

  testWidgets('Ledger display preferences reclaim optional row columns', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final sourceTransaction = migrated.transactions.firstWhere(
      (transaction) =>
          transaction.type == v2_transaction.TransactionType.expense,
    );
    final splitCategories = migrated.categories
        .where((category) => category.kind == v2_category.CategoryKind.expense)
        .take(2)
        .toList(growable: false);
    final splitTransaction = sourceTransaction.copyWith(
      status: v2_transaction.TransactionStatus.pending,
      splitLines: [
        v2_transaction.TransactionSplitLine(
          id: 'display-split-a',
          categoryId: splitCategories.first.id,
          amountMinor: sourceTransaction.amountMinor ~/ 2,
        ),
        v2_transaction.TransactionSplitLine(
          id: 'display-split-b',
          categoryId: splitCategories.last.id,
          amountMinor:
              sourceTransaction.amountMinor -
              sourceTransaction.amountMinor ~/ 2,
        ),
      ],
    );
    final comparisonTransaction = migrated.transactions
        .firstWhere(
          (transaction) =>
              transaction.id != splitTransaction.id && !transaction.isDeleted,
        )
        .copyWith(date: DateTime(2026, 8, 14, 9, 21));
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        transactions: [
          for (final transaction in migrated.transactions)
            if (transaction.id == splitTransaction.id)
              splitTransaction
            else if (transaction.id == comparisonTransaction.id)
              comparisonTransaction
            else
              transaction,
        ],
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('ledger-icon-${splitTransaction.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('ledger-timestamp-slot-${splitTransaction.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('ledger-split-slot-${splitTransaction.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('ledger-split-indicator-${splitTransaction.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('ledger-pending-indicator-${splitTransaction.id}')),
      findsOneWidget,
    );
    final detailsKey = ValueKey(
      'ledger-metadata-details-${splitTransaction.id}',
    );
    final timestampSlotKey = ValueKey(
      'ledger-timestamp-slot-${splitTransaction.id}',
    );
    final splitSlotKey = ValueKey('ledger-split-slot-${splitTransaction.id}');
    final phoneMetadataWidth = tester.getSize(find.byKey(detailsKey)).width;
    final timestampSlotWidth = tester
        .getSize(find.byKey(timestampSlotKey))
        .width;

    // The protected timestamp column follows the real localized label and
    // remains visible; metadata is still the first zone to yield on a narrow
    // screen or under a wide test font.
    expect(timestampSlotWidth, greaterThan(0));
    expect(phoneMetadataWidth, greaterThan(0));
    expect(
      tester.widget<Text>(find.byKey(detailsKey)).data,
      contains(splitCategories.first.name),
    );
    expect(
      tester.widget<Text>(find.byKey(detailsKey)).data,
      contains(splitCategories.last.name),
    );

    final comparisonTimestampKey = ValueKey(
      'ledger-timestamp-slot-${comparisonTransaction.id}',
    );
    final comparisonSplitSlotKey = ValueKey(
      'ledger-split-slot-${comparisonTransaction.id}',
    );
    expect(find.byKey(comparisonTimestampKey), findsOneWidget);
    expect(find.byKey(comparisonSplitSlotKey), findsOneWidget);
    // Timestamp glyphs remain aligned to one protected trailing edge even
    // though shorter labels no longer reserve unused leading width.
    expect(
      tester.getTopRight(find.byKey(timestampSlotKey)).dx,
      tester.getTopRight(find.byKey(comparisonTimestampKey)).dx,
    );
    expect(
      tester.getTopLeft(find.byKey(splitSlotKey)).dx,
      tester.getTopLeft(find.byKey(comparisonSplitSlotKey)).dx,
    );
    final splitSecondaryAmountSlot = find.byKey(
      ValueKey('ledger-secondary-amount-slot-${splitTransaction.id}'),
    );
    final comparisonSecondaryAmountSlot = find.byKey(
      ValueKey('ledger-secondary-amount-slot-${comparisonTransaction.id}'),
    );
    expect(splitSecondaryAmountSlot, findsOneWidget);
    expect(comparisonSecondaryAmountSlot, findsOneWidget);
    expect(tester.getSize(splitSecondaryAmountSlot).width, 44);
    expect(
      tester.getTopLeft(splitSecondaryAmountSlot).dx,
      tester.getTopLeft(comparisonSecondaryAmountSlot).dx,
    );

    tester.view.physicalSize = const Size(1024, 1366);
    await tester.pumpAndSettle();
    final tabletMetadataWidth = tester.getSize(find.byKey(detailsKey)).width;
    expect(tester.getSize(splitSecondaryAmountSlot).width, 230);
    expect(tabletMetadataWidth, greaterThan(phoneMetadataWidth));

    await dataStore.savePreferences(
      dataStore.preferences.copyWith(
        showLedgerIcons: false,
        showLedgerTimestamps: false,
        showLedgerSplitIndicator: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('ledger-icon-${splitTransaction.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('ledger-timestamp-slot-${splitTransaction.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('ledger-split-slot-${splitTransaction.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('ledger-split-indicator-${splitTransaction.id}')),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(detailsKey)).width,
      greaterThan(tabletMetadataWidth),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'account Ledger metadata omits current account and names transfer peer',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final currentAccount = migrated.accounts.first;
      final otherAccount = migrated.accounts.firstWhere(
        (account) => account.id != currentAccount.id,
      );
      final category = migrated.categories.firstWhere(
        (item) => item.kind == v2_category.CategoryKind.expense,
      );
      final now = DateTime(2026, 8, 14, 13, 45);
      final expense = v2_transaction.TransactionRecord(
        id: 'account-metadata-expense',
        type: v2_transaction.TransactionType.expense,
        accountId: currentAccount.id,
        categoryId: category.id,
        date: now,
        payee: 'Account Metadata Expense',
        amountMinor: 1250,
        status: v2_transaction.TransactionStatus.pending,
        sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
      );
      final unrelatedPending = v2_transaction.TransactionRecord(
        id: 'other-account-pending',
        type: v2_transaction.TransactionType.expense,
        accountId: otherAccount.id,
        categoryId: category.id,
        date: now.subtract(const Duration(minutes: 2)),
        payee: 'Other Account Pending',
        amountMinor: 9900,
        status: v2_transaction.TransactionStatus.pending,
        sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
      );
      final transfer = v2_transaction.TransactionRecord(
        id: 'account-metadata-transfer',
        type: v2_transaction.TransactionType.transfer,
        accountId: currentAccount.id,
        transferAccountId: otherAccount.id,
        date: now.subtract(const Duration(minutes: 1)),
        payee: 'Account Metadata Transfer',
        amountMinor: 5000,
        sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          accounts: [currentAccount, otherAccount],
          transactions: [expense, transfer, unrelatedPending],
          preferences: migrated.preferences.copyWith(showRunningBalance: true),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: FinanceDataStoreScope(
            store: dataStore,
            child: Scaffold(
              body: SingleChildScrollView(
                child: LedgerView(initialAccountFilterId: currentAccount.id),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expenseMetadata = tester.widget<Text>(
        find.byKey(
          const ValueKey('ledger-metadata-details-account-metadata-expense'),
        ),
      );
      final transferMetadata = tester.widget<Text>(
        find.byKey(
          const ValueKey('ledger-metadata-details-account-metadata-transfer'),
        ),
      );
      expect(expenseMetadata.data, category.name);
      expect(expenseMetadata.data, isNot(contains(currentAccount.name)));
      expect(transferMetadata.data, 'Transfer • ${otherAccount.name}');
      expect(
        find.byKey(
          const ValueKey('ledger-running-balance-account-metadata-transfer'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey(
                  'ledger-secondary-amount-slot-account-metadata-transfer',
                ),
              ),
            )
            .width,
        220,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('ledger-pending-summary-count')),
            )
            .data,
        '1',
      );
      expect(find.text('Other Account Pending'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('ledger-pending-summary-card')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account Metadata Expense'), findsOneWidget);
      expect(find.text('Other Account Pending'), findsNothing);
      expect(
        tester
            .widget<LedgerView>(
              find.byKey(const ValueKey('pending-filtered-ledger')),
            )
            .initialAccountFilterId,
        currentAccount.id,
      );
    },
  );

  testWidgets('pending Ledger row shows status and quick actions clear it', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final source = migrated.transactions.firstWhere(
      (transaction) =>
          transaction.type == v2_transaction.TransactionType.expense,
    );
    final pending = source.copyWith(
      payee: 'Pending Ledger Test',
      status: v2_transaction.TransactionStatus.pending,
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        transactions: [
          for (final transaction in migrated.transactions)
            if (transaction.id == pending.id) pending else transaction,
        ],
      ),
    );
    final originalBalance = dataStore.balanceForAccount(pending.accountId);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('ledger-pending-indicator-${pending.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-pending-summary-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-pending-summary-count')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ledger-pending-summary-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-ledger-screen')), findsOneWidget);
    expect(ledgerRowWithText('Pending Ledger Test'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-ledger-screen')), findsNothing);
    expect(ledgerRowWithText('Pending Ledger Test'), findsOneWidget);
    await tester.longPress(ledgerRowWithText('Pending Ledger Test'));
    await tester.pumpAndSettle();
    expect(find.text('Mark Cleared'), findsOneWidget);
    await tester.tap(find.text('Mark Cleared'));
    await tester.pumpAndSettle();

    expect(
      dataStore.transactions
          .singleWhere((item) => item.id == pending.id)
          .status,
      v2_transaction.TransactionStatus.cleared,
    );
    expect(dataStore.balanceForAccount(pending.accountId), originalBalance);
    expect(
      find.byKey(ValueKey('ledger-pending-indicator-${pending.id}')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ledger-pending-summary-card')),
      findsNothing,
    );

    await tester.longPress(ledgerRowWithText('Pending Ledger Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark Pending'));
    await tester.pumpAndSettle();
    expect(
      dataStore.transactions
          .singleWhere((item) => item.id == pending.id)
          .status,
      v2_transaction.TransactionStatus.pending,
    );
    await tester.drag(
      ledgerRowWithText('Pending Ledger Test'),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    expect(
      dataStore.transactions
          .singleWhere((item) => item.id == pending.id)
          .status,
      v2_transaction.TransactionStatus.cleared,
    );
    expect(dataStore.balanceForAccount(pending.accountId), originalBalance);
  });

  testWidgets('scheduled payment can create a pending linked transaction', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dueDate = DateTime.now();
    final schedule = rentSchedule(nextDate: dueDate);
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(scheduledTransactions: [schedule]),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Paid'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mark-paid-pending-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    final generated = dataStore.transactions.singleWhere(
      (transaction) => transaction.scheduledTransactionId == schedule.id,
    );
    expect(generated.status, v2_transaction.TransactionStatus.pending);
    expect(generated.scheduledOccurrenceDate, isNotNull);
    expect(dataStore.scheduledTransactions.single.occurrences, hasLength(1));
    expect(
      dataStore.scheduledTransactions.single.occurrences.single.transactionId,
      generated.id,
    );
  });

  testWidgets(
    'transaction form uses an independent Pending toggle and keeps Notes last',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final legacyStore = FinanceStore.seeded();
      final dataStore = FinanceDataStore(
        dataSet: const V1SnapshotMigrator().migrate(
          legacyStore.snapshot().toJson(),
        ),
      );
      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();

      final pendingToggle = find.byKey(
        const ValueKey('transaction-pending-toggle'),
      );
      final pendingSwitch = find.descendant(
        of: pendingToggle,
        matching: find.byType(Switch),
      );
      final scheduleToggle = find.byKey(
        const ValueKey('transaction-schedule-toggle'),
      );
      expect(pendingToggle, findsOneWidget);
      expect(tester.widget<Switch>(pendingSwitch).value, isFalse);
      expect(
        find.text('Use for transactions that haven’t cleared yet'),
        findsOneWidget,
      );
      expect(find.text('Status'), findsNothing);
      expect(find.text('Cleared'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('transaction-date'))).dy,
        lessThan(tester.getTopLeft(pendingToggle).dy),
      );
      expect(
        tester.getTopLeft(pendingToggle).dy,
        lessThan(tester.getTopLeft(scheduleToggle).dy),
      );
      expect(
        tester.getTopLeft(scheduleToggle).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('transaction-note'))).dy,
        ),
      );

      final hapticCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            hapticCalls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.tap(pendingToggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(pendingSwitch).value, isTrue);
      expect(
        hapticCalls.where(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        hasLength(1),
      );
      expect(
        tester
            .widget<Switch>(
              find.descendant(
                of: scheduleToggle,
                matching: find.byType(Switch),
              ),
            )
            .value,
        isFalse,
      );

      await tester.tap(scheduleToggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(pendingSwitch).value, isTrue);
      expect(
        tester
            .widget<Switch>(
              find.descendant(
                of: scheduleToggle,
                matching: find.byType(Switch),
              ),
            )
            .value,
        isTrue,
      );

      await tester.tap(find.text('Choose account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checking').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-payee')),
        'Pending scheduled note',
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '4321',
      );
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('transaction-note')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-note')),
        'Pending with a future schedule',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = dataStore.transactions.singleWhere(
        (transaction) => transaction.payee == 'Pending scheduled note',
      );
      expect(saved.status, v2_transaction.TransactionStatus.pending);
      expect(saved.note, 'Pending with a future schedule');
      expect(saved.scheduledTransactionId, isNotNull);
      expect(
        dataStore.scheduledTransactions.any(
          (schedule) => schedule.id == saved.scheduledTransactionId,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'editing a Pending transaction loads silently and clearing changes status only',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final original = migrated.transactions.firstWhere(
        (transaction) => transaction.payee == 'Walmart',
      );
      final pending = original.copyWith(
        status: v2_transaction.TransactionStatus.pending,
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          transactions: [
            for (final transaction in migrated.transactions)
              if (transaction.id == pending.id) pending else transaction,
          ],
        ),
      );
      final originalBalance = dataStore.balanceForAccount(pending.accountId);
      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.text('Ledger').last);
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Walmart').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      final pendingToggle = find.byKey(
        const ValueKey('transaction-pending-toggle'),
      );
      final pendingSwitch = find.descendant(
        of: pendingToggle,
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(pendingSwitch).value, isTrue);
      final hapticCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            hapticCalls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pump();
      expect(hapticCalls, isEmpty);

      await tester.ensureVisible(pendingToggle);
      await tester.pumpAndSettle();
      await tester.tap(pendingToggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(pendingSwitch).value, isFalse);
      expect(
        hapticCalls.where(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        hasLength(1),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = dataStore.transactions.singleWhere(
        (transaction) => transaction.id == pending.id,
      );
      expect(saved.status, v2_transaction.TransactionStatus.cleared);
      expect(saved.amountMinor, pending.amountMinor);
      expect(saved.categoryId, pending.categoryId);
      expect(saved.note, pending.note);
      expect(dataStore.balanceForAccount(pending.accountId), originalBalance);
    },
  );

  testWidgets('Pending transaction form remains usable across iOS widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in const [
      Size(320, 568),
      Size(390, 844),
      Size(1024, 768),
    ]) {
      tester.view.physicalSize = size;
      final legacyStore = FinanceStore.seeded();
      await tester.pumpWidget(
        MoneyTallyApp(
          store: legacyStore,
          dataStore: FinanceDataStore(
            dataSet: const V1SnapshotMigrator().migrate(
              legacyStore.snapshot().toJson(),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('transaction-pending-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-schedule-toggle')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('transaction-note')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('transaction-note')), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Failed at $size');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  test('scheduled undo uses type-specific labels', () {
    expect(
      undoScheduledTransactionLabel(v2_transaction.TransactionType.expense),
      'Undo Payment',
    );
    expect(
      undoScheduledTransactionLabel(v2_transaction.TransactionType.income),
      'Undo Income',
    );
    expect(
      undoScheduledTransactionLabel(v2_transaction.TransactionType.transfer),
      'Undo Transfer',
    );
    expect(
      undoScheduledTransactionConfirmationTitle(
        v2_transaction.TransactionType.transfer,
      ),
      'Undo this scheduled transfer?',
    );
  });

  testWidgets('ledger filters by account type category and date', (
    tester,
  ) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-account-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit Card').last);
    await tester.pumpAndSettle();

    expect(ledgerRowWithText('Diner'), findsOneWidget);
    expect(ledgerRowWithText('Walmart'), findsNothing);
    expect(ledgerRowWithText('Settlement'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('All Types'), findsOneWidget);
    expect(find.text('Credit Card'), findsNWidgets(2));
    expect(find.text('All Categories'), findsOneWidget);
    expect(find.text('Any Date'), findsOneWidget);
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('Jump to Month'), findsOneWidget);
    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-type-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();

    expect(ledgerRowWithText('Settlement'), findsOneWidget);
    expect(ledgerRowWithText('Walmart'), findsNothing);
    expect(ledgerRowWithText('Diner'), findsNothing);

    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-category-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();

    expect(ledgerRowWithText('Diner'), findsOneWidget);
    expect(ledgerRowWithText('Walmart'), findsNothing);
    expect(ledgerRowWithText('Settlement'), findsNothing);

    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-date-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();

    expect(ledgerRowWithText('Diner'), findsNothing);
    expect(ledgerRowWithText('Walmart'), findsNothing);
    expect(ledgerRowWithText('Settlement'), findsNothing);
    expect(find.text('No activities match'), findsOneWidget);
  });

  testWidgets(
    'ledger filter button clearly distinguishes neutral and active states',
    (tester) async {
      await tester.pumpWidget(MoneyTallyApp());
      await tester.tap(find.text('Ledger').last);
      await tester.pumpAndSettle();

      IconButton filterButton() => tester.widget<IconButton>(
        find.byKey(const ValueKey('ledger-filter-button')),
      );
      Color? background(IconButton button) =>
          button.style?.backgroundColor?.resolve(<WidgetState>{});
      Color? foreground(IconButton button) =>
          button.style?.foregroundColor?.resolve(<WidgetState>{});
      BorderSide? side(IconButton button) =>
          button.style?.side?.resolve(<WidgetState>{});

      final neutralButton = filterButton();
      final neutralBackground = background(neutralButton);
      expect(find.byTooltip('Filters'), findsOneWidget);
      expect(side(neutralButton), BorderSide.none);

      await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ledger-filter-account-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit Card').last);
      await tester.pumpAndSettle();

      final oneFilterButton = filterButton();
      final oneFilterBackground = background(oneFilterButton);
      final oneFilterForeground = foreground(oneFilterButton);
      final oneFilterSide = side(oneFilterButton);
      expect(find.byTooltip('Filters active (1)'), findsOneWidget);
      expect(oneFilterBackground, isNot(neutralBackground));
      expect(oneFilterForeground, AppColors.accent);
      expect(oneFilterSide, isNotNull);
      expect(oneFilterSide!.width, 1.15);
      expect(oneFilterSide.color.a, greaterThan(0.40));

      await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ledger-filter-type-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Income').last);
      await tester.pumpAndSettle();

      final twoFilterButton = filterButton();
      expect(find.byTooltip('Filters active (2)'), findsOneWidget);
      expect(background(twoFilterButton), oneFilterBackground);
      expect(foreground(twoFilterButton), oneFilterForeground);
      expect(side(twoFilterButton), oneFilterSide);

      await tester.tap(find.byTooltip('Clear filters'));
      await tester.pumpAndSettle();

      final clearedButton = filterButton();
      expect(find.byTooltip('Filters'), findsOneWidget);
      expect(background(clearedButton), neutralBackground);
      expect(side(clearedButton), BorderSide.none);
    },
  );

  testWidgets(
    'filtered main Ledger edge swipe clears filters only after commit',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(MoneyTallyApp());
      await tester.tap(find.text('Ledger').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ledger-filter-account-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit Card').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Filters active (1)'), findsOneWidget);
      expect(ledgerRowWithText('Walmart'), findsNothing);

      final swipeRegion = find.byKey(
        const ValueKey('filtered-ledger-back-swipe'),
      );
      expect(tester.widget<Listener>(swipeRegion).onPointerDown, isNotNull);
      final swipeRect = tester.getRect(swipeRegion);
      expect(swipeRect.left, 0);
      await tester.dragFrom(
        Offset(swipeRect.left + 5, swipeRect.center.dy),
        const Offset(30, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Filters active (1)'), findsOneWidget);

      await tester.dragFrom(
        Offset(swipeRect.left + 5, swipeRect.center.dy),
        const Offset(140, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Filters'), findsOneWidget);
      expect(find.text('Ledger'), findsWidgets);
      expect(ledgerRowWithText('Walmart'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('filtered main Ledger X uses the same clear-filter result', (
    tester,
  ) async {
    await tester.pumpWidget(MoneyTallyApp());
    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-type-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Filters active (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Filters'), findsOneWidget);
    expect(find.text('Ledger'), findsWidgets);
    expect(ledgerRowWithText('Walmart'), findsOneWidget);
  });

  testWidgets('ledger active filter treatment remains distinct in dark mode', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        preferences: migrated.preferences.copyWith(
          appearanceMode: AppearanceMode.dark,
        ),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-filter-account-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit Card').last);
    await tester.pumpAndSettle();

    final activeButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('ledger-filter-button')),
    );
    final activeSide = activeButton.style?.side?.resolve(<WidgetState>{});
    final activeBackground = activeButton.style?.backgroundColor?.resolve(
      <WidgetState>{},
    );
    expect(find.byTooltip('Filters active (1)'), findsOneWidget);
    expect(activeSide, isNotNull);
    expect(activeSide!.color.a, greaterThan(0.50));
    expect(activeBackground, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ledger long press can duplicate and delete transaction', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(
      dataStore.transactions.map((transaction) => transaction.payee),
      contains('Walmart copy'),
    );
    expect(find.text('Walmart copy'), findsOneWidget);

    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    final original = dataStore.transactions.singleWhere(
      (transaction) => transaction.payee == 'Walmart',
    );
    expect(original.isDeleted, isTrue);
    expect(find.text('Walmart'), findsNothing);
    expect(find.text('Walmart copy'), findsOneWidget);
  });

  testWidgets('ledger long press can edit transaction', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Switch>(
            find.descendant(
              of: find.byKey(const ValueKey('transaction-pending-toggle')),
              matching: find.byType(Switch),
            ),
          )
          .value,
      isFalse,
    );

    await tester.enterText(
      find.byKey(const ValueKey('transaction-payee')),
      'Walmart Grocery',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-note')),
      'Pickup order',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '1234',
    );
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(
      find.byKey(const ValueKey('transaction-single-category-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-split-category-field')),
      findsNothing,
    );
    expect(find.text('Split transaction'), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final edited = dataStore.transactions.singleWhere(
      (transaction) => transaction.payee == 'Walmart Grocery',
    );
    expect(edited.amountMinor, 1234);
    expect(edited.note, 'Pickup order');
    expect(edited.type, v2_transaction.TransactionType.expense);
    expect(edited.splitLines, isEmpty);
    expect(edited.isCategorySplit, isFalse);
    expect(find.text('Walmart Grocery'), findsOneWidget);
  });

  testWidgets('ledger long press can edit transfer transaction', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);
    await dataStore.addTransfer(
      fromAccountId: 'checking',
      toAccountId: 'cash',
      // Keep this row at the top of the current Ledger so the long-press
      // exercise is independent of the device's current viewport height.
      date: DateTime.now(),
      payee: 'ATM cash',
      amountMinor: 5000,
      note: 'Original note',
    );
    final originalDate = dataStore.transactions
        .singleWhere((transaction) => transaction.payee == 'ATM cash')
        .date;

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    final atmCash = find.text('ATM cash').first;
    await tester.ensureVisible(atmCash);
    await tester.longPress(atmCash);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Transaction'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Payee'), findsNothing);
    expect(find.text('Split Categories'), findsNothing);
    expect(find.text('Add a description (optional)'), findsOneWidget);
    final transferTypeSelector = tester
        .widget<SegmentedButton<v2_transaction.TransactionType>>(
          find.byType(SegmentedButton<v2_transaction.TransactionType>),
        );
    expect(transferTypeSelector.selected, {
      v2_transaction.TransactionType.transfer,
    });
    expect(transferTypeSelector.showSelectedIcon, isFalse);
    final transferAmountField = tester.widget<TextField>(
      find.byKey(const ValueKey('transfer-amount')),
    );
    expect(transferAmountField.autofocus, isFalse);
    expect(find.byKey(const ValueKey('transfer-date')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transfer-schedule-toggle')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-payee')),
      'Cash refill',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-note')),
      'Updated note',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-amount')),
      '7500',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final edited = dataStore.transactions.singleWhere(
      (transaction) => transaction.payee == 'Cash refill',
    );
    expect(edited.type, v2_transaction.TransactionType.transfer);
    expect(edited.accountId, 'checking');
    expect(edited.transferAccountId, 'cash');
    expect(edited.categoryId, isNull);
    expect(edited.amountMinor, 7500);
    expect(edited.date, originalDate);
    expect(edited.note, 'Updated note');
    expect(find.text('Cash refill'), findsOneWidget);
  });

  testWidgets('editing a transfer can create one future schedule', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await dataStore.addTransfer(
      fromAccountId: 'checking',
      toAccountId: 'cash',
      date: DateTime.now(),
      payee: 'Scheduled cash refill',
      amountMinor: 5000,
    );
    final original = dataStore.transactions.singleWhere(
      (transaction) => transaction.payee == 'Scheduled cash refill',
    );
    final initialScheduleCount = dataStore.scheduledTransactions.length;

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    final scheduledCashRefill = find.text('Scheduled cash refill').first;
    await tester.ensureVisible(scheduledCashRefill);
    await tester.longPress(scheduledCashRefill);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('transfer-schedule-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final updated = dataStore.transactions.singleWhere(
      (transaction) => transaction.id == original.id,
    );
    expect(updated.scheduledTransactionId, isNotNull);
    expect(
      dataStore.scheduledTransactions,
      hasLength(initialScheduleCount + 1),
    );
    final schedule = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == updated.scheduledTransactionId,
    );
    expect(schedule.type, v2_transaction.TransactionType.transfer);
    expect(schedule.accountId, 'checking');
    expect(schedule.transferAccountId, 'cash');
    expect(schedule.nextDate.isAfter(DateTime.now()), isTrue);
  });

  testWidgets('ledger long press can split transaction', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();

    final splitSection = find.byKey(
      const ValueKey('transaction-split-category-field'),
    );
    expect(splitSection, findsOneWidget);
    expect(
      find.descendant(of: splitSection, matching: find.byType(TextField)),
      findsNWidgets(2),
    );

    await tester.tap(
      find.descendant(of: splitSection, matching: find.text('Choose category')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add New Category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-new-category-name')),
      'Split Supplies',
    );
    await tester.tap(
      find.byKey(const ValueKey('transaction-save-new-category')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Split Supplies'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    final splitAmountFields = find.descendant(
      of: splitSection,
      matching: find.byType(TextField),
    );
    expect(splitAmountFields, findsNWidgets(2));
    await tester.enterText(splitAmountFields.at(1), '3428');
    await tester.pump();
    expect(find.text('Balanced'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(find.text(r'$30.00'), findsOneWidget);
    expect(find.text(r'$34.28'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('transaction-use-single-category')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('transaction-use-single-category')),
    );
    await tester.pumpAndSettle();
    final discardConfirmation = find.byType(AlertDialog);
    expect(discardConfirmation, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: discardConfirmation,
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(splitSection, findsOneWidget);
    expect(splitAmountFields, findsNWidgets(2));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final transaction = dataStore.transactions.singleWhere(
      (item) => item.payee == 'Walmart',
    );
    expect(transaction.isSplit, isTrue);
    expect(transaction.splitLines.length, 2);
    expect(transaction.splitTotalMinor, transaction.amountMinor);
    expect(
      dataStore.categoryById(transaction.splitLines.last.categoryId).name,
      'Split Supplies',
    );
  });

  testWidgets('ledger long press can make transaction scheduled', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);
    final initialScheduleCount = dataStore.scheduledTransactions.length;

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make Scheduled'));
    await tester.pumpAndSettle();

    expect(find.text('Create Scheduled Transaction'), findsOneWidget);
    expect(find.text('Walmart'), findsWidgets);
    expect(find.text(r'$64.28'), findsWidgets);
    expect(find.text('Checking'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scheduled-single-category-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scheduled-split-category-field')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('scheduled-next-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('scheduled-alert-time')), findsOneWidget);
    expect(dataStore.scheduledTransactions, hasLength(initialScheduleCount));
    await tester.ensureVisible(
      find.byKey(const ValueKey('scheduled-frequency')),
    );
    await tester.tap(find.byKey(const ValueKey('scheduled-frequency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('scheduled-alert')));
    await tester.tap(find.byKey(const ValueKey('scheduled-alert')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 day before').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final schedule = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'Walmart',
    );
    expect(schedule.type, v2_transaction.TransactionType.expense);
    expect(schedule.accountId, 'checking');
    expect(schedule.categoryId, 'walmart');
    expect(schedule.frequency, v2_scheduled.RecurrenceFrequency.weekly);
    expect(schedule.alertPreference, v2_scheduled.AlertPreference.oneDayBefore);
    expect(schedule.customAlertTimeMinutes, 9 * 60);
    expect(schedule.nextDate.isAfter(DateTime.now()), isTrue);

    final transaction = dataStore.transactions.singleWhere(
      (item) => item.payee == 'Walmart',
    );
    expect(transaction.scheduledTransactionId, schedule.id);
  });

  testWidgets('ledger long press can make transfer scheduled', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);
    final initialScheduleCount = dataStore.scheduledTransactions.length;
    await dataStore.addTransfer(
      fromAccountId: 'checking',
      toAccountId: 'cash',
      date: DateTime.now(),
      payee: 'ATM transfer',
      amountMinor: 5000,
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    final atmTransfer = find.text('ATM transfer').first;
    await tester.ensureVisible(atmTransfer);
    await tester.longPress(atmTransfer);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make Scheduled'));
    await tester.pumpAndSettle();

    expect(find.text('Create Scheduled Transaction'), findsOneWidget);
    expect(find.text('ATM transfer'), findsWidgets);
    expect(find.text(r'$50.00'), findsWidgets);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(dataStore.scheduledTransactions, hasLength(initialScheduleCount));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final schedule = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'ATM transfer',
    );
    expect(schedule.type, v2_transaction.TransactionType.transfer);
    expect(schedule.accountId, 'checking');
    expect(schedule.transferAccountId, 'cash');
    expect(schedule.categoryId, isNull);
    expect(schedule.frequency, v2_scheduled.RecurrenceFrequency.monthly);

    final transaction = dataStore.transactions.singleWhere(
      (item) => item.payee == 'ATM transfer',
    );
    expect(transaction.scheduledTransactionId, schedule.id);
  });

  testWidgets('ledger Make Scheduled cancel creates nothing', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    final original = dataStore.transactions.singleWhere(
      (transaction) => transaction.payee == 'Walmart',
    );
    final initialScheduleCount = dataStore.scheduledTransactions.length;
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make Scheduled'));
    await tester.pumpAndSettle();
    expect(find.text('Create Scheduled Transaction'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(dataStore.scheduledTransactions, hasLength(initialScheduleCount));
    expect(
      dataStore.transactions.singleWhere((item) => item.id == original.id),
      original,
    );
  });

  testWidgets('add transaction dialog honors default income preference', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            defaultTransactionType: DefaultTransactionType.income,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();

    final segmented = tester
        .widget<SegmentedButton<v2_transaction.TransactionType>>(
          find.byType(SegmentedButton<v2_transaction.TransactionType>),
        );

    expect(segmented.selected, {v2_transaction.TransactionType.income});
  });

  testWidgets('normal expense and income use category-first split workflow', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();

    final singleCategory = find.byKey(
      const ValueKey('transaction-single-category-field'),
    );
    expect(singleCategory, findsOneWidget);
    expect(
      find.descendant(
        of: singleCategory,
        matching: find.text('Choose category'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-split-category-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('transaction-enable-split')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('transaction-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transaction-enable-split')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('transaction-enable-split')));
    await tester.pumpAndSettle();
    final splitSection = find.byKey(
      const ValueKey('transaction-split-category-field'),
    );
    expect(splitSection, findsOneWidget);
    expect(
      find.descendant(of: splitSection, matching: find.text('Choose category')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: splitSection, matching: find.byType(TextField)),
      findsNWidgets(2),
    );
    expect(
      tester
          .widget<TextField>(
            find
                .descendant(of: splitSection, matching: find.byType(TextField))
                .at(1),
          )
          .autofocus,
      isTrue,
    );
    var splitAmountFields = tester
        .widgetList<TextField>(
          find.descendant(of: splitSection, matching: find.byType(TextField)),
        )
        .toList();
    expect(splitAmountFields[1].focusNode?.hasFocus, isTrue);
    expect(splitAmountFields[0].focusNode?.hasFocus, isFalse);
    final newSplitAmount = tester.widget<AmountEntryField>(
      find
          .descendant(of: splitSection, matching: find.byType(AmountEntryField))
          .at(1),
    );
    expect(newSplitAmount.replaceZeroOnFirstInput, isTrue);
    expect(newSplitAmount.selectAllOnFocus, isFalse);
    expect(find.byKey(const ValueKey('transaction-add-split')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('transaction-add-split')),
    );
    await tester.tap(find.byKey(const ValueKey('transaction-add-split')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: splitSection, matching: find.byType(TextField)),
      findsNWidgets(3),
    );
    splitAmountFields = tester
        .widgetList<TextField>(
          find.descendant(of: splitSection, matching: find.byType(TextField)),
        )
        .toList();
    expect(splitAmountFields[2].focusNode?.hasFocus, isTrue);
    expect(splitAmountFields[1].focusNode?.hasFocus, isFalse);
    expect(
      tester
          .widgetList<AmountEntryField>(
            find.descendant(
              of: splitSection,
              matching: find.byType(AmountEntryField),
            ),
          )
          .map((field) => field.initialMinor),
      [0, 0, 0],
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('transaction-add-split')),
    );
    await tester.tap(find.byKey(const ValueKey('transaction-add-split')));
    await tester.pumpAndSettle();
    splitAmountFields = tester
        .widgetList<TextField>(
          find.descendant(of: splitSection, matching: find.byType(TextField)),
        )
        .toList();
    expect(splitAmountFields, hasLength(4));
    expect(splitAmountFields[3].focusNode?.hasFocus, isTrue);
    expect(
      splitAmountFields
          .take(3)
          .every((field) => field.focusNode?.hasFocus == false),
      isTrue,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('transaction-use-single-category')),
    );
    await tester.tap(
      find.byKey(const ValueKey('transaction-use-single-category')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.byKey(const ValueKey('transaction-single-category-field')),
      findsOneWidget,
    );
    expect(splitSection, findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transaction-single-category-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-split-category-field')),
      findsNothing,
    );
  });

  testWidgets(
    'add transaction schedules future occurrences only when enabled',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final legacyStore = FinanceStore.seeded();
      final dataStore = FinanceDataStore(
        dataSet: const V1SnapshotMigrator().migrate(
          legacyStore.snapshot().toJson(),
        ),
      );
      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );

      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      expect(find.text('Schedule future occurrences'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction-schedule-controls')),
        findsNothing,
      );

      await tester.tap(find.text('Choose account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checking').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-payee')),
        'Future utility',
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '12500',
      );
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining').last);
      await tester.pumpAndSettle();
      final scheduleToggle = find.byKey(
        const ValueKey('transaction-schedule-toggle'),
      );
      await tester.ensureVisible(scheduleToggle);
      await tester.tap(scheduleToggle);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('transaction-schedule-controls')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-schedule-first-date')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-schedule-time')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('transaction-schedule-frequency')),
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-schedule-frequency')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekly').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('transaction-schedule-alert')),
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-schedule-alert')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 day before').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(
        find.widgetWithText(FilledButton, 'Save'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final current = dataStore.transactions.singleWhere(
        (transaction) => transaction.payee == 'Future utility',
      );
      final scheduled = dataStore.scheduledTransactions.singleWhere(
        (item) => item.payee == 'Future utility',
      );
      expect(current.scheduledTransactionId, scheduled.id);
      expect(current.splitLines, isEmpty);
      expect(current.isCategorySplit, isFalse);
      expect(scheduled.amountMinor, 12500);
      expect(scheduled.splitLines, isEmpty);
      expect(scheduled.isCategorySplit, isFalse);
      expect(scheduled.frequency, v2_scheduled.RecurrenceFrequency.weekly);
      expect(
        scheduled.alertPreference,
        v2_scheduled.AlertPreference.oneDayBefore,
      );
      expect(scheduled.customAlertTimeMinutes, 9 * 60);
      expect(scheduled.nextDate.isAfter(DateTime.now()), isTrue);
      expect(
        dataStore.transactions.where(
          (transaction) => transaction.payee == 'Future utility',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('disabling future scheduling creates only the transaction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    final initialScheduleCount = dataStore.scheduledTransactions.length;
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checking').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-payee')),
      'One time only',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '2500',
    );
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('transaction-schedule-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      dataStore.transactions.any(
        (transaction) => transaction.payee == 'One time only',
      ),
      isTrue,
    );
    expect(dataStore.scheduledTransactions, hasLength(initialScheduleCount));
  });

  testWidgets('add transaction honors default transfer preference', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            defaultTransactionType: DefaultTransactionType.transfer,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    expect(find.text('Add Transaction'), findsOneWidget);
  });

  testWidgets('add transaction honors last used transfer preference', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            defaultTransactionType: DefaultTransactionType.lastUsed,
            lastUsedTransactionType: v2_transaction.TransactionType.transfer,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    expect(find.text('Add Transaction'), findsOneWidget);
  });

  testWidgets(
    'transaction category flow creates, selects, and preserves form',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final legacyStore = FinanceStore.seeded();
      final dataSet = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      const localRepository = LocalFinanceDataSetRepository(
        storageKey: 'transaction_category_flow_test',
      );
      final dataStore = FinanceDataStore(
        dataSet: dataSet,
        localRepository: localRepository,
      );

      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );

      await tester.tap(find.text('Ledger').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checking'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('transaction-payee')),
        'Hardware Store',
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '4599',
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-note')),
        'Paint and fasteners',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('transaction-single-category-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transaction-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add New Category'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('transaction-new-category-name')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-new-category-name')),
        'Road Supplies',
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-save-new-category')),
      );
      await tester.pumpAndSettle();

      final created = dataStore.categories.singleWhere(
        (category) => category.name == 'Road Supplies',
      );
      expect(created.kind, v2_category.CategoryKind.expense);
      expect(created.parentCategoryId, isNull);
      expect(find.text('Road Supplies'), findsOneWidget);
      expect(find.text('Checking'), findsWidgets);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transaction-payee')))
            .controller!
            .text,
        'Hardware Store',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transaction-note')))
            .controller!
            .text,
        'Paint and fasteners',
      );
      expect(find.text('Today'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transaction-amount')))
            .controller!
            .text,
        r'$45.99',
      );

      final reloadedStore = await FinanceDataStore.load(
        localRepository: localRepository,
      );
      expect(
        reloadedStore.categories.any((category) => category.id == created.id),
        isTrue,
      );

      await tester.tap(find.text('Road Supplies'));
      await tester.pumpAndSettle();
      expect(find.text('Road Supplies'), findsWidgets);
    },
  );

  testWidgets(
    'transaction overlays use the captured store with nested navigators',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final dataStore = FinanceDataStore(
        dataSet: const V1SnapshotMigrator().migrate(
          legacyStore.snapshot().toJson(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MoneyTallyApp(store: legacyStore, dataStore: dataStore),
        ),
      );

      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      expect(find.text('Add New Category'), findsOneWidget);
      await tester.tap(find.text('Dining').last);
      await tester.pumpAndSettle();

      final payeeField = find.byKey(const ValueKey('transaction-payee'));
      await tester.enterText(payeeField, 'Wal');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payee-suggestion-Walmart')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(dataStore.preferences.savedPayeeNames, contains('Walmart'));
    },
  );

  testWidgets(
    'transaction category flow creates income and expense categories',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final dataSet = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final dataStore = FinanceDataStore(dataSet: dataSet);
      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );

      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Income').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add New Category'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-new-category-name')),
        'Consulting',
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-save-new-category')),
      );
      await tester.pumpAndSettle();

      final incomeCategory = dataStore.categories.singleWhere(
        (category) => category.name == 'Consulting',
      );
      expect(incomeCategory.kind, v2_category.CategoryKind.income);
      expect(find.text('Consulting'), findsOneWidget);

      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add New Category'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-new-category-name')),
        'Work Lunches',
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-save-new-category')),
      );
      await tester.pumpAndSettle();

      final expenseCategory = dataStore.categories.singleWhere(
        (category) => category.name == 'Work Lunches',
      );
      expect(expenseCategory.kind, v2_category.CategoryKind.expense);
      expect(expenseCategory.parentCategoryId, isNull);
      expect(find.text('Work Lunches'), findsOneWidget);
    },
  );

  testWidgets(
    'transaction category creation validates and cancel returns to picker',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final dataStore = FinanceDataStore(
        dataSet: const V1SnapshotMigrator().migrate(
          legacyStore.snapshot().toJson(),
        ),
      );
      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add New Category'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('transaction-save-new-category')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter a category name.'), findsOneWidget);
      expect(find.text('Add Category'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Choose Category'), findsOneWidget);
      expect(find.text('Add Category'), findsNothing);
      expect(find.text('Add Transaction'), findsOneWidget);
    },
  );

  testWidgets('transaction category creation blocks duplicate saves', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final repository = BlockingLocalFinanceRepository();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
      localRepository: repository,
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add New Category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-new-category-name')),
      'One Tap Only',
    );

    final save = find.byKey(const ValueKey('transaction-save-new-category'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(
      dataStore.categories.where((category) => category.name == 'One Tap Only'),
      hasLength(1),
    );
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    repository.saveCompleter.complete();
    await tester.pumpAndSettle();
    expect(find.text('One Tap Only'), findsOneWidget);
  });

  testWidgets('transaction category persistence errors remain visible', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
      localRepository: const FailingLocalFinanceRepository(),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add New Category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-new-category-name')),
      'Cannot Persist',
    );
    await tester.tap(
      find.byKey(const ValueKey('transaction-save-new-category')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('The category could not be saved. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Add Category'), findsOneWidget);
    expect(
      dataStore.categories.any((category) => category.name == 'Cannot Persist'),
      isFalse,
    );
  });

  testWidgets(
    'transaction category picker excludes archived and deleted categories',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final hiddenCategories = [
        v2_category.CategoryRecord(
          id: 'archived-hidden',
          name: 'Archived Hidden',
          kind: v2_category.CategoryKind.expense,
          isArchived: true,
          sync: v2_sync.SyncMetadata.fresh(),
        ),
        v2_category.CategoryRecord(
          id: 'deleted-hidden',
          name: 'Deleted Hidden',
          kind: v2_category.CategoryKind.expense,
          sync: v2_sync.SyncMetadata.fresh().deleted(),
        ),
      ];
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          categories: [...migrated.categories, ...hiddenCategories],
        ),
      );
      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();

      expect(find.text('Archived Hidden'), findsNothing);
      expect(find.text('Deleted Hidden'), findsNothing);
    },
  );

  testWidgets(
    'transaction category picker shows hierarchy selection and fixed add action',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final hierarchy = [
        v2_category.CategoryRecord(
          id: 'picker-parent',
          name: 'Home Costs',
          kind: v2_category.CategoryKind.expense,
          sync: v2_sync.SyncMetadata.fresh(),
        ),
        v2_category.CategoryRecord(
          id: 'picker-child',
          name: 'Repairs',
          kind: v2_category.CategoryKind.expense,
          parentCategoryId: 'picker-parent',
          sync: v2_sync.SyncMetadata.fresh(),
        ),
        v2_category.CategoryRecord(
          id: 'picker-other-parent',
          name: 'Auto Costs',
          kind: v2_category.CategoryKind.expense,
          sync: v2_sync.SyncMetadata.fresh(),
        ),
        v2_category.CategoryRecord(
          id: 'picker-other-child',
          name: 'Fuel',
          kind: v2_category.CategoryKind.expense,
          parentCategoryId: 'picker-other-parent',
          sync: v2_sync.SyncMetadata.fresh(),
        ),
      ];
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          categories: [...migrated.categories, ...hierarchy],
        ),
      );
      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();

      expect(find.text('Choose Category'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('category-picker-add-new')),
        findsOneWidget,
      );
      expect(find.text('1 subcategory'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('category-picker-hierarchy-picker-child')),
        findsNothing,
      );
      expect(find.text('Repairs'), findsNothing);
      expect(find.text('Fuel'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('category-picker-toggle-picker-parent')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Repairs'), findsOneWidget);
      expect(find.text('Fuel'), findsNothing);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      expect(find.text('Repairs'), findsNothing);
      expect(find.text('Fuel'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('category-picker-toggle-picker-parent')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('category-picker-row-picker-child')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Repairs'), findsOneWidget);

      await tester.tap(find.text('Repairs'));
      await tester.pumpAndSettle();
      final selectedRow = find.byKey(
        const ValueKey('category-picker-row-picker-child'),
      );
      expect(
        find.descendant(
          of: selectedRow,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'category picker reveals children expanded near the viewport bottom',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final extraCategories = [
        for (var index = 0; index < 12; index++)
          v2_category.CategoryRecord(
            id: 'reveal-filler-$index',
            name: 'A Reveal Filler $index',
            kind: v2_category.CategoryKind.expense,
            sync: v2_sync.SyncMetadata.fresh(),
          ),
        v2_category.CategoryRecord(
          id: 'reveal-parent',
          name: 'Truck',
          kind: v2_category.CategoryKind.expense,
          sync: v2_sync.SyncMetadata.fresh(),
        ),
        for (var index = 0; index < 5; index++)
          v2_category.CategoryRecord(
            id: 'reveal-child-$index',
            name: 'Truck Child $index',
            kind: v2_category.CategoryKind.expense,
            parentCategoryId: 'reveal-parent',
            sync: v2_sync.SyncMetadata.fresh(),
          ),
      ];
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          categories: [...migrated.categories, ...extraCategories],
        ),
      );
      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();

      final toggle = find.byKey(
        const ValueKey('category-picker-toggle-reveal-parent'),
      );
      await tester.scrollUntilVisible(
        toggle,
        350,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('category-picker-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      final parent = find.byKey(
        const ValueKey('category-picker-row-reveal-parent'),
      );
      final lastChild = find.byKey(
        const ValueKey('category-picker-row-reveal-child-4'),
      );
      expect(parent, findsOneWidget);
      expect(lastChild, findsOneWidget);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('category-picker-list')),
      );
      expect(tester.getRect(parent).top, greaterThanOrEqualTo(viewport.top));
      expect(
        tester.getRect(lastChild).bottom,
        lessThanOrEqualTo(viewport.bottom),
      );
    },
  );

  testWidgets('transaction category picker filters transaction type', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: migrated);
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('category-picker-row-dining')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('category-picker-row-income')),
      findsNothing,
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('category-picker-row-income')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('category-picker-row-dining')),
      findsNothing,
    );
  });

  testWidgets('transaction category picker keeps add action in empty state', (
    tester,
  ) async {
    final emptyLegacyStore = FinanceStore.seeded();
    emptyLegacyStore.categories.clear();
    final emptyDataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        emptyLegacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: emptyLegacyStore, dataStore: emptyDataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category-picker-empty')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('category-picker-add-new')),
      findsOneWidget,
    );
  });

  testWidgets('transaction category picker remains readable in dark mode', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        preferences: migrated.preferences.copyWith(
          appearanceMode: AppearanceMode.dark,
        ),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();

    expect(find.text('Choose Category'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('category-picker-row-dining')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('add transaction dialog saves entered date', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checking').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('transaction-payee')),
      'Hardware Store',
    );
    final dateRow = find.text(fullMonthDateLabel(DateTime.now()));
    await tester.ensureVisible(dateRow);
    await tester.pumpAndSettle();
    await tester.tap(dateRow);
    await tester.pumpAndSettle();
    await tester.tap(find.text('4').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-note')),
      'Paint and fasteners',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '4599',
    );
    await tester.pump();
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save').last,
    );
    expect(saveButton.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();

    final transaction = dataStore.transactions.singleWhere(
      (item) => item.payee == 'Hardware Store',
    );
    final now = DateTime.now();
    expect(
      DateUtils.dateOnly(transaction.date),
      DateTime(now.year, now.month, 4),
    );
    expect(transaction.amountMinor, 4599);
    expect(transaction.note, 'Paint and fasteners');
  });

  testWidgets('transaction payee suggestion can be selected', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();

    final payeeField = find.byKey(const ValueKey('transaction-payee'));
    await tester.enterText(payeeField, 'Wal');
    await tester.pumpAndSettle();
    final walmartSuggestion = find.byKey(
      const ValueKey('payee-suggestion-Walmart'),
    );
    expect(walmartSuggestion, findsOneWidget);

    await tester.tap(walmartSuggestion);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(payeeField).controller!.text, 'Walmart');
    expect(walmartSuggestion, findsNothing);
  });

  testWidgets('floating add menu opens income transaction dialog', (
    tester,
  ) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsWidgets);
    expect(find.text('Transfer'), findsOneWidget);

    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();

    expect(find.text('Add Transaction'), findsOneWidget);
    final segmented = tester
        .widget<SegmentedButton<v2_transaction.TransactionType>>(
          find.byType(SegmentedButton<v2_transaction.TransactionType>),
        );
    expect(segmented.selected, {v2_transaction.TransactionType.income});
  });

  testWidgets('floating add button honors left placement preference', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            floatingAddButtonPosition: FloatingAddButtonPosition.left,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));

    expect(
      scaffold.floatingActionButtonLocation,
      FloatingActionButtonLocation.startFloat,
    );
  });

  testWidgets('floating add button honors center placement preference', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            floatingAddButtonPosition: FloatingAddButtonPosition.center,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));

    expect(
      scaffold.floatingActionButtonLocation,
      FloatingActionButtonLocation.centerFloat,
    );
  });

  testWidgets('floating add account creates visible account', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Travel Fund');
    await tester.enterText(fields.at(1), '123.45');
    final groupBalanceOption = find.widgetWithText(
      TrackmarkSwitchListTile,
      'Include in Group Totals',
    );
    final netWorthOption = find.widgetWithText(
      TrackmarkSwitchListTile,
      'Include in net worth',
    );
    await tester.ensureVisible(groupBalanceOption);
    await tester.tap(groupBalanceOption);
    await tester.ensureVisible(netWorthOption);
    await tester.tap(netWorthOption);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Travel Fund'), findsOneWidget);
    expect(find.text(r'$123.45'), findsOneWidget);
    final account = dataStore.accounts.singleWhere(
      (account) => account.name == 'Travel Fund',
    );
    expect(account.includeInGroupBalance, isFalse);
    expect(account.includeInNetWorth, isFalse);
  });

  testWidgets('new credit card receives the standard icon and teal accent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Travel Card');
    await tester.tap(find.text('Checking').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Credit Card').last);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Teal'), findsOneWidget);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final account = dataStore.accounts.singleWhere(
      (account) => account.name == 'Travel Card',
    );
    expect(account.creditCardIconId, CreditCardAppearanceCatalog.defaultIconId);
    expect(
      account.creditCardAccentId,
      CreditCardAppearanceCatalog.defaultAccentId,
    );
  });

  testWidgets('floating add transfer creates first-class transfer', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);
    final checking = dataStore.accounts.singleWhere(
      (account) => account.name == 'Checking',
    );
    final cash = dataStore.accounts.singleWhere(
      (account) => account.name == 'Cash',
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('transfer-to-'))).onTap,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('transfer-from-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checking').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InkWell>(find.byKey(ValueKey('transfer-to-${checking.id}')))
          .onTap,
      isNotNull,
    );
    await tester.tap(find.byKey(ValueKey('transfer-to-${checking.id}')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Checking'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Cash').last);
    await tester.pumpAndSettle();

    final transferSheet = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == 'TransactionSheetFrame',
    );
    expect(transferSheet, findsOneWidget);
    expect(
      find.descendant(
        of: transferSheet,
        matching: find.textContaining('Balance'),
      ),
      findsNWidgets(2),
    );

    final now = DateTime.now();
    final transferDate = DateTime(now.year, now.month, now.day);
    await tester.ensureVisible(find.byKey(const ValueKey('transfer-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transfer-note')),
      'ATM cash',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-payee')),
      'Savings transfer',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-amount')),
      '5000',
    );
    await tester.pumpAndSettle();
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(saveButton.onPressed, isNotNull);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final transfer = dataStore.transactions.singleWhere(
      (transaction) =>
          transaction.type == v2_transaction.TransactionType.transfer,
    );
    expect(transfer.accountId, checking.id);
    expect(transfer.transferAccountId, cash.id);
    expect(transfer.payee, 'Savings transfer');
    expect(DateUtils.dateOnly(transfer.date), transferDate);
    expect(transfer.note, 'ATM cash');
    expect(
      dataStore.preferences.lastUsedTransactionType,
      v2_transaction.TransactionType.transfer,
    );
    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    expect(find.text(r'$1,802.40'), findsWidgets);
    expect(find.text(r'$297.00'), findsWidgets);
  });

  testWidgets('new transfer can also create one future schedule', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-from-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checking').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-to-checking')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.text('Checking'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Cash').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transfer-payee')),
      'Weekly settlement',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-amount')),
      '4000',
    );
    final toggle = find.byKey(const ValueKey('transfer-schedule-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transfer-schedule-controls')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final transfer = dataStore.transactions.singleWhere(
      (item) => item.payee == 'Weekly settlement',
    );
    final schedule = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'Weekly settlement',
    );
    expect(transfer.transferAccountId, 'cash');
    expect(transfer.scheduledTransactionId, schedule.id);
    expect(schedule.type, v2_transaction.TransactionType.transfer);
    expect(schedule.accountId, 'checking');
    expect(schedule.transferAccountId, 'cash');
    expect(schedule.nextDate.isAfter(DateTime.now()), isTrue);
  });

  testWidgets('floating add scheduled transaction creates v2 schedule', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Scheduled Transaction'));
    await tester.tap(find.text('Scheduled Transaction'));
    await tester.pumpAndSettle();

    final scheduledTypeSelector = tester
        .widget<SegmentedButton<v2_transaction.TransactionType>>(
          find.byType(SegmentedButton<v2_transaction.TransactionType>),
        );
    expect(scheduledTypeSelector.showSelectedIcon, isFalse);
    expect(find.text('Create Scheduled Transaction'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('scheduled-amount')))
          .autofocus,
      isFalse,
    );
    expect(find.text('Choose account'), findsOneWidget);
    expect(find.text('Choose category'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('scheduled-account')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.text(dataStore.accounts.first.name),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-payee')),
      'Rent',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('scheduled-payee')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('scheduled-frequency')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scheduled-frequency')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('scheduled-payee')))
          .focusNode!
          .hasFocus,
      isFalse,
    );
    await tester.tap(find.text('Once').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-amount')),
      '900.00',
    );
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('scheduled-category')),
    );
    await tester.tap(find.byKey(const ValueKey('scheduled-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'Rent',
    );
    expect(scheduled.type, v2_transaction.TransactionType.expense);
    expect(scheduled.amountMinor, 90000);
    final today = DateTime.now();
    expect(scheduled.nextDate, DateTime(today.year, today.month, today.day));
    expect(scheduled.frequency, v2_scheduled.RecurrenceFrequency.once);
    expect(scheduled.categoryId, 'dining');

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();

    expect(find.text('All Scheduled'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-activity-filter-picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-activity-filter')),
      findsNothing,
    );

    expect(find.text('Rent'), findsOneWidget);
  });

  testWidgets('scheduled add defaults to the selected future calendar date', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDate = DateTime(today.year, today.month + 1, 7);

    await tester.pumpWidget(MoneyTallyApp());
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey(
          'scheduled-calendar-day-${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();

    expect(find.text('Create Scheduled Transaction'), findsOneWidget);
    expect(find.text(fullMonthDateLabel(selectedDate)), findsOneWidget);
  });

  testWidgets('scheduled expense saves balanced inline category splits', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Scheduled Transaction'));
    await tester.tap(find.text('Scheduled Transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scheduled-account')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.text(dataStore.accounts.first.name),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-amount')),
      '100.00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-payee')),
      'Split groceries',
    );
    expect(
      find.byKey(const ValueKey('scheduled-single-category-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('scheduled-enable-split')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('scheduled-category')),
    );
    await tester.tap(find.byKey(const ValueKey('scheduled-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('scheduled-enable-split')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('scheduled-enable-split')));
    await tester.pumpAndSettle();
    final splitSection = find.byKey(
      const ValueKey('scheduled-split-category-field'),
    );
    expect(
      find.descendant(of: splitSection, matching: find.byType(TextField)),
      findsNWidgets(2),
    );
    expect(
      tester
          .widget<TextField>(
            find
                .descendant(of: splitSection, matching: find.byType(TextField))
                .at(1),
          )
          .autofocus,
      isTrue,
    );
    final newSplitAmount = tester.widget<AmountEntryField>(
      find
          .descendant(of: splitSection, matching: find.byType(AmountEntryField))
          .at(1),
    );
    expect(newSplitAmount.replaceZeroOnFirstInput, isTrue);
    expect(newSplitAmount.selectAllOnFocus, isFalse);
    await tester.tap(find.byKey(const ValueKey('scheduled-split-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snacks').last);
    await tester.pumpAndSettle();

    final splitAmounts = find.descendant(
      of: splitSection,
      matching: find.byType(TextField),
    );
    expect(splitAmounts, findsNWidgets(2));
    await tester.enterText(splitAmounts.at(1), '4000');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('scheduled-split-remaining')),
      findsOneWidget,
    );
    expect(find.text('Balanced'), findsOneWidget);

    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'Split groceries',
    );
    expect(scheduled.splitLines, hasLength(2));
    expect(scheduled.splitLines[0].categoryId, 'dining');
    expect(scheduled.splitLines[0].amountMinor, 6000);
    expect(scheduled.splitLines[1].categoryId, 'snacks');
    expect(scheduled.splitLines[1].amountMinor, 4000);
    expect(scheduled.hasValidSplitTotal, isTrue);
  });

  testWidgets('scheduled income split can create and select a new category', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Scheduled Transaction'));
    await tester.tap(find.text('Scheduled Transaction'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<v2_transaction.TransactionType>),
        matching: find.text('Income'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scheduled-account')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.text(dataStore.accounts.first.name),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-amount')),
      '1000.00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-payee')),
      'Split income',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('scheduled-category')),
    );
    await tester.tap(find.byKey(const ValueKey('scheduled-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scheduled-enable-split')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scheduled-split-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add New Category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-new-category-name')),
      'Bonus Income',
    );
    await tester.tap(
      find.byKey(const ValueKey('transaction-save-new-category')),
    );
    await tester.pumpAndSettle();

    final splitSection = find.byKey(
      const ValueKey('scheduled-split-category-field'),
    );
    final splitAmounts = find.descendant(
      of: splitSection,
      matching: find.byType(TextField),
    );
    await tester.enterText(splitAmounts.at(1), '25000');
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'Split income',
    );
    expect(scheduled.type, v2_transaction.TransactionType.income);
    expect(scheduled.splitLines, hasLength(2));
    expect(scheduled.splitLines[0].amountMinor, 75000);
    expect(scheduled.splitLines[1].amountMinor, 25000);
    expect(
      dataStore.categoryById(scheduled.splitLines[1].categoryId).name,
      'Bonus Income',
    );
  });

  testWidgets('scheduled date and time pickers use polished theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MoneyTallyApp());
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Scheduled Transaction'));
    await tester.tap(find.text('Scheduled Transaction'));
    await tester.pumpAndSettle();

    final dateRow = find.byKey(const ValueKey('scheduled-next-date'));
    await tester.ensureVisible(dateRow);
    await tester.tap(dateRow);
    await tester.pumpAndSettle();

    final dateTheme = Theme.of(
      tester.element(find.byType(CalendarDatePicker)),
    ).datePickerTheme;
    expect(dateTheme.backgroundColor, Colors.white);
    expect(
      dateTheme.dayBackgroundColor!.resolve({WidgetState.selected}),
      AppTheme.accent,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    final timeRow = find.byKey(const ValueKey('scheduled-alert-time'));
    await tester.ensureVisible(timeRow);
    await tester.tap(timeRow);
    await tester.pumpAndSettle();

    final timeTheme = Theme.of(
      tester.element(find.byType(TimePickerDialog)),
    ).timePickerTheme;
    expect(timeTheme.backgroundColor, Colors.white);
    expect(timeTheme.dialHandColor, AppTheme.accent);
    expect(
      WidgetStateProperty.resolveAs<Color?>(timeTheme.hourMinuteColor, {
        WidgetState.selected,
      }),
      AppTheme.accent.withValues(alpha: 0.14),
    );
  });

  testWidgets('scheduled income uses polished fields and saves', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Scheduled Transaction'));
    await tester.tap(find.text('Scheduled Transaction'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<v2_transaction.TransactionType>),
        matching: find.text('Income'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose account'), findsOneWidget);
    expect(find.text('Choose category'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scheduled-account')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.text(dataStore.accounts.first.name),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-amount')),
      '1250.00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-payee')),
      'Payroll',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('scheduled-category')),
    );
    await tester.tap(find.byKey(const ValueKey('scheduled-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'Payroll',
    );
    expect(scheduled.type, v2_transaction.TransactionType.income);
    expect(scheduled.amountMinor, 125000);
    expect(scheduled.accountId, isNotEmpty);
    expect(scheduled.categoryId, 'income');
  });

  testWidgets('scheduled transfer saves distinct accounts and description', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Scheduled Transaction'));
    await tester.tap(find.text('Scheduled Transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    expect(find.text('From Account'), findsOneWidget);
    expect(find.text('To Account'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Payee'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    final sourceAccount = dataStore.accounts.first;
    final destinationAccount = dataStore.accounts.firstWhere(
      (account) => account.id != sourceAccount.id,
    );
    expect(find.text('Choose account'), findsOneWidget);
    expect(find.text('Choose a source account first'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scheduled-account')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.text(sourceAccount.name),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(ValueKey('scheduled-to-${sourceAccount.id}')),
    );
    await tester.tap(find.byKey(ValueKey('scheduled-to-${sourceAccount.id}')));
    await tester.pumpAndSettle();
    final destinationPicker = find.byType(BottomSheet).last;
    expect(
      find.descendant(
        of: destinationPicker,
        matching: find.text(sourceAccount.name),
      ),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: destinationPicker,
        matching: find.text(destinationAccount.name),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-amount')),
      '300.00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-payee')),
      'Weekly settlement',
    );
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'Weekly settlement',
    );
    expect(scheduled.type, v2_transaction.TransactionType.transfer);
    expect(scheduled.accountId, isNot(scheduled.transferAccountId));
    expect(scheduled.transferAccountId, isNotNull);
    expect(scheduled.categoryId, isNull);
    expect(scheduled.amountMinor, 30000);
  });

  testWidgets('account long press opens details before editing', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataSet = migrated.copyWith(
      accounts: [
        ...migrated.accounts,
        v2_account.AccountRecord(
          id: 'cloud-only',
          name: 'Cloud Only',
          type: v2_account.AccountType.checking,
          openingBalanceMinor: 0,
          sync: v2_sync.SyncMetadata.fresh(),
        ),
      ],
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Cloud Only'));
    await tester.pumpAndSettle();
    expect(find.text('Account Details'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    await tester.tap(find.text('Account Details'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('account-details-view')), findsOneWidget);
    expect(find.text('Account Information'), findsOneWidget);
    expect(find.text('Balance Options'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Main Checking');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Main Checking'), findsWidgets);
    expect(dataStore.accountById('cloud-only').name, 'Main Checking');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-details-view')), findsNothing);
  });

  testWidgets(
    'account ledger is a pushed detail and Back restores Accounts position',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final extraAccounts = List.generate(
        14,
        (index) => v2_account.AccountRecord(
          id: 'scroll-account-$index',
          name: 'Scroll Account $index',
          type: v2_account.AccountType.checking,
          openingBalanceMinor: index * 100,
          sortOrder: 1000 + index,
          sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
        ),
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          accounts: [...migrated.accounts, ...extraAccounts],
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.accounts,
          ),
        ),
      );

      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.pumpAndSettle();

      final targetCard = find.byWidgetPredicate(
        (widget) =>
            widget is AccountCard && widget.account.id == 'scroll-account-12',
      );
      await tester.ensureVisible(targetCard);
      await tester.pumpAndSettle();
      final accountsScroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final positionBeforePush = accountsScroll.position.pixels;
      expect(positionBeforePush, greaterThan(0));

      await tester.tap(targetCard);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-ledger-screen')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LedgerView>(find.byType(LedgerView))
            .initialAccountFilterId,
        'scroll-account-12',
      );

      await tester.tap(find.byKey(const ValueKey('account-ledger-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-ledger-screen')), findsNothing);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        closeTo(positionBeforePush, 0.1),
      );

      await tester.tap(find.text('Ledger').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LedgerView>(find.byType(LedgerView))
            .initialAccountFilterId,
        isNull,
      );
    },
  );

  testWidgets('account ledger supports the native iOS edge swipe back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.accounts,
          ),
        );
    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: migrated),
      ),
    );
    await tester.pumpAndSettle();

    final accountCard = find.byWidgetPredicate(
      (widget) => widget is AccountCard && widget.account.id == 'checking',
    );
    await tester.ensureVisible(accountCard);
    await tester.tap(accountCard);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-ledger-screen')), findsOneWidget);

    await tester.timedDragFrom(
      const Offset(1, 420),
      const Offset(360, 0),
      const Duration(milliseconds: 350),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-ledger-screen')), findsNothing);
    expect(find.text('Accounts'), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('account edit can toggle balance inclusion flags', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Checking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final groupBalanceSwitch = find.widgetWithText(
      TrackmarkSwitchListTile,
      'Include in Group Totals',
    );
    final netWorthSwitch = find.widgetWithText(
      TrackmarkSwitchListTile,
      'Include in net worth',
    );
    await tester.ensureVisible(groupBalanceSwitch);
    await tester.tap(groupBalanceSwitch);
    await tester.ensureVisible(netWorthSwitch);
    await tester.tap(netWorthSwitch);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final account = dataStore.accountById('checking');
    expect(account.includeInGroupBalance, isFalse);
    expect(account.includeInNetWorth, isFalse);
  });

  testWidgets('account long press can change account type', (tester) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Checking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Cash').last);
    await tester.pumpAndSettle();

    expect(dataStore.accountById('checking').type, v2_account.AccountType.cash);
  });

  testWidgets('account edit can set credit card limit', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.accounts,
          ),
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    final card = find.byWidgetPredicate(
      (widget) => widget is AccountCard && widget.account.name == 'Credit Card',
    );
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.longPress(card);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account Details'));
    await tester.pumpAndSettle();
    expect(find.text('Credit Available'), findsOneWidget);
    expect(find.text('Credit Limit'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Credit limit'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('account-credit-limit')),
      '250000',
    );
    await tester.pump();
    expect(find.text(r'$2,500.00'), findsOneWidget);
    expect(find.text('Appearance'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('credit-card-icon-picker-row')));
    await tester.pumpAndSettle();
    expect(CreditCardAppearanceCatalog.icons, hasLength(4));
    await tester.tap(
      find.byKey(const ValueKey('credit-card-icon-rectangleStackFill')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('credit-card-accent-picker-row')),
    );
    await tester.pumpAndSettle();
    expect(CreditCardAppearanceCatalog.accents, hasLength(12));
    await tester.tap(find.byKey(const ValueKey('credit-card-accent-purple')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final account = dataStore.accountById('card');
    expect(account.creditLimitMinor, 250000);
    expect(account.creditCardIconId, 'rectangleStackFill');
    expect(account.creditCardAccentId, 'purple');
    expect(dataStore.creditAvailableMinorForAccount('card'), 206178);
    expect(find.text(r'Credit Available $2,061.78 of $2,500.00'), findsWidgets);
  });

  testWidgets('credit card Account Details shows read-only Credit Insights', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final card = migrated.accounts.singleWhere(
      (account) => account.type == v2_account.AccountType.creditCard,
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        accounts: [
          for (final account in migrated.accounts)
            if (account.id == card.id)
              account.copyWith(
                creditLimitMinor: 250000,
                interestEstimationEnabled: true,
                creditInsightsDisclosureAcknowledged: true,
                annualPercentageRate: 28.49,
                statementClosingDay: 15,
                paymentDueDay: 7,
              )
            else
              account,
        ],
        preferences: const UserPreferences(launchScreen: LaunchScreen.accounts),
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    final accountCard = find.byWidgetPredicate(
      (widget) => widget is AccountCard && widget.account.id == card.id,
    );
    await tester.ensureVisible(accountCard);
    await tester.longPress(accountCard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account Details'));
    await tester.pumpAndSettle();

    final details = find.byKey(const ValueKey('account-details-view'));
    for (final label in [
      'Credit Available',
      'Credit Limit',
      'Credit Insights',
      'APR',
      '28.49%',
      'Next Statement',
      'Payment Due',
      'Estimated Interest',
      'Projected Statement',
      'Statement Closing Day',
      'Payment Due Day',
    ]) {
      expect(
        find.descendant(of: details, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: details,
        matching: find.byTooltip('About Credit Insights'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: details,
        matching: find.byType(TrackmarkSwitchListTile),
      ),
      findsNothing,
    );
  });

  testWidgets('enabled credit card shows additive Credit Insights preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final account = v2_account.AccountRecord(
      id: 'credit-insights',
      name: 'Credit Card',
      type: v2_account.AccountType.creditCard,
      openingBalanceMinor: 0,
      creditLimitMinor: 170000,
      interestEstimationEnabled: true,
      annualPercentageRate: 29.99,
      statementClosingDay: 15,
      paymentDueDay: 7,
      sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountCard(account: account, balanceMinor: -113786),
        ),
      ),
    );

    expect(find.text(r'Credit Available $562.14 of $1,700.00'), findsOneWidget);
    expect(find.text('Next Statement'), findsOneWidget);
    expect(find.text('Payment Due'), findsOneWidget);
    expect(find.text('APR'), findsNothing);
    expect(find.text('29.99%'), findsNothing);
    expect(find.text('Projected Statement'), findsOneWidget);
    expect(find.text('Estimated Interest'), findsOneWidget);
    expect(find.text('67% utilized'), findsOneWidget);
    expect(find.textContaining('≈'), findsNothing);

    final utilizationBox = tester.renderObject<RenderBox>(
      find.text('67% utilized'),
    );
    expect(
      utilizationBox.size.width,
      greaterThanOrEqualTo(creditUtilizationLabelMinWidth),
    );

    final nextStatementLabel = tester.widget<Text>(find.text('Next Statement'));
    final paymentDueLabel = tester.widget<Text>(find.text('Payment Due'));
    final estimatedInterestLabel = tester.widget<Text>(
      find.text('Estimated Interest'),
    );
    final projectedStatementLabel = tester.widget<Text>(
      find.text('Projected Statement'),
    );
    for (final label in [
      paymentDueLabel,
      estimatedInterestLabel,
      projectedStatementLabel,
    ]) {
      expect(label.style?.fontSize, nextStatementLabel.style?.fontSize);
      expect(label.style?.fontWeight, nextStatementLabel.style?.fontWeight);
      expect(label.style?.color, nextStatementLabel.style?.color);
      expect(label.style?.height, nextStatementLabel.style?.height);
      expect(label.textAlign, TextAlign.center);
    }
    expect(nextStatementLabel.textAlign, TextAlign.center);

    expect(
      tester
          .widget<Expanded>(
            find
                .ancestor(
                  of: find.text('Next Statement'),
                  matching: find.byType(Expanded),
                )
                .first,
          )
          .flex,
      23,
    );
    expect(
      tester
          .widget<Expanded>(
            find
                .ancestor(
                  of: find.text('Payment Due'),
                  matching: find.byType(Expanded),
                )
                .first,
          )
          .flex,
      20,
    );
    expect(
      tester
          .widget<Expanded>(
            find
                .ancestor(
                  of: find.text('Estimated Interest'),
                  matching: find.byType(Expanded),
                )
                .first,
          )
          .flex,
      27,
    );
    expect(
      tester
          .widget<Expanded>(
            find
                .ancestor(
                  of: find.text('Projected Statement'),
                  matching: find.byType(Expanded),
                )
                .first,
          )
          .flex,
      30,
    );

    final projectedMetric = find
        .ancestor(
          of: find.text('Projected Statement'),
          matching: find.byType(Expanded),
        )
        .first;
    final projectedValue = tester.widget<AccountBalanceText>(
      find.descendant(
        of: projectedMetric,
        matching: find.byType(AccountBalanceText),
      ),
    );
    expect(projectedValue.fontSize, 14);
    expect(projectedValue.fontWeight, FontWeight.w700);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long Projected Statement keeps peer base style and scales safely',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final account = v2_account.AccountRecord(
        id: 'large-projected-statement',
        name: 'Large Card',
        type: v2_account.AccountType.creditCard,
        openingBalanceMinor: -987654321,
        creditLimitMinor: 1200000000,
        interestEstimationEnabled: true,
        annualPercentageRate: 29.99,
        statementClosingDay: 28,
        paymentDueDay: 20,
        sync: v2_sync.SyncMetadata.fresh(
          now: DateTime.now().subtract(const Duration(days: 90)),
          deviceId: 'test',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountCard(account: account, balanceMinor: -987654321),
            ),
          ),
        ),
      );

      final projectedMetric = find
          .ancestor(
            of: find.text('Projected Statement'),
            matching: find.byType(Expanded),
          )
          .first;
      final projectedValue = tester.widget<AccountBalanceText>(
        find.descendant(
          of: projectedMetric,
          matching: find.byType(AccountBalanceText),
        ),
      );
      expect(projectedValue.fontSize, 14);
      expect(projectedValue.fontWeight, FontWeight.w700);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'credit card Payment Due follows paid schedule and Undo immediately',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sync = v2_sync.SyncMetadata.fresh(
        now: DateTime(2026, 8, 1),
        deviceId: 'test',
      );
      final checking = v2_account.AccountRecord(
        id: 'payment-source',
        name: 'Checking',
        type: v2_account.AccountType.checking,
        openingBalanceMinor: 100000,
        sync: sync,
      );
      final card = v2_account.AccountRecord(
        id: 'payment-card',
        name: 'Payment Card',
        type: v2_account.AccountType.creditCard,
        openingBalanceMinor: -50000,
        creditLimitMinor: 200000,
        interestEstimationEnabled: true,
        annualPercentageRate: 24,
        statementClosingDay: 8,
        paymentDueDay: 28,
        sync: sync,
      );
      final dueDate = DateTime(2026, 8, 28);
      final schedule = v2_scheduled.ScheduledTransactionRecord(
        id: 'payment-card-schedule',
        type: v2_transaction.TransactionType.transfer,
        accountId: checking.id,
        transferAccountId: card.id,
        payee: 'Payment Card',
        amountMinor: 10000,
        nextDate: dueDate,
        frequency: v2_scheduled.RecurrenceFrequency.monthly,
        sync: sync,
      );
      final dataStore = FinanceDataStore(
        dataSet: FinanceDataSet(
          accounts: [checking, card],
          categories: const [],
          transactions: const [],
          scheduledTransactions: [schedule],
          budgets: const [],
          preferences: const UserPreferences(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FinanceDataStoreScope(
            store: dataStore,
            child: Builder(
              builder: (context) {
                final watchedStore = FinanceDataStoreScope.watch(context);
                return Scaffold(
                  body: AccountCard(
                    account: card,
                    balanceMinor: watchedStore.balanceForAccount(card.id),
                    transactions: watchedStore.transactions,
                    nextScheduledPaymentDueDate: watchedStore
                        .nextCreditCardPaymentDueDate(card.id),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aug 28'), findsOneWidget);

      final transaction = await completeScheduledTransactionPayment(
        dataStore,
        schedule,
        scheduledDate: dueDate,
        actualAmountMinor: 10000,
        paymentDate: DateTime(2026, 8, 14, 9, 30),
        payee: 'Payment Card',
        note: 'Paid early',
        status: v2_transaction.TransactionStatus.pending,
      );
      await tester.pumpAndSettle();

      expect(transaction.status, v2_transaction.TransactionStatus.pending);
      expect(find.text('Aug 28'), findsNothing);
      expect(find.text('Sep 28'), findsOneWidget);

      await dataStore.undoScheduledPayment(
        transaction.id,
        now: DateTime(2026, 8, 14),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aug 28'), findsOneWidget);
      expect(find.text('Sep 28'), findsNothing);

      final syncedSchedule = schedule.copyWith(
        nextDate: DateTime(2026, 9, 28),
        occurrences: [
          v2_scheduled.ScheduledOccurrenceRecord(
            scheduledDate: dueDate,
            plannedAmountMinor: 10000,
            status: v2_scheduled.ScheduledOccurrenceStatus.paid,
            actualAmountMinor: 10000,
            actualPaymentDate: DateTime(2026, 8, 14, 9, 30),
            transactionId: 'synced-payment',
          ),
        ],
        sync: schedule.sync.touched(
          now: DateTime(2026, 8, 15),
          deviceId: 'remote',
        ),
      );
      await dataStore.replaceDataSet(
        dataStore.dataSet.copyWith(scheduledTransactions: [syncedSchedule]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sep 28'), findsOneWidget);
    },
  );

  testWidgets('complete Credit Insights estimate has no status indicator', (
    tester,
  ) async {
    final now = DateTime.now();
    final account = _creditInsightsWidgetAccount(
      createdAt: DateTime(now.year, now.month - 2, now.day),
      statementClosingDay: now.day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountCard(account: account, balanceMinor: -100000),
        ),
      ),
    );

    expect(find.text('Partial'), findsNothing);
    expect(find.text('Not enough history'), findsNothing);
    expect(
      find.byKey(const ValueKey('credit-estimate-status-partial')),
      findsNothing,
    );
  });

  testWidgets('partial estimate shows amount, status, and explanation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final account = _creditInsightsWidgetAccount(
      createdAt: now,
      statementClosingDay: now.day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountCard(account: account, balanceMinor: -100000),
        ),
      ),
    );

    expect(find.text('Partial'), findsOneWidget);
    expect(find.text(r'$0.66'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('credit-estimate-status-partial')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Partial Estimate'), findsOneWidget);
    expect(
      find.textContaining('part of this statement cycle’s account history'),
      findsOneWidget,
    );
  });

  testWidgets('insufficient history replaces precise estimate with status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final account = _creditInsightsWidgetAccount(
      createdAt: DateTime(now.year, now.month, now.day + 1),
      statementClosingDay: now.day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountCard(account: account, balanceMinor: -100000),
        ),
      ),
    );

    expect(find.text('Not enough history'), findsOneWidget);
    expect(find.text(r'$0.00'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('credit-estimate-status-insufficientHistory')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not Enough History'), findsOneWidget);
  });

  testWidgets('partial indicator disappears when estimate becomes complete', (
    tester,
  ) async {
    final now = DateTime.now();
    final partialAccount = _creditInsightsWidgetAccount(
      createdAt: now,
      statementClosingDay: now.day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountCard(account: partialAccount, balanceMinor: -100000),
        ),
      ),
    );
    expect(find.text('Partial'), findsOneWidget);

    final completeAccount = _creditInsightsWidgetAccount(
      createdAt: DateTime(now.year, now.month - 2, now.day),
      statementClosingDay: now.day,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountCard(account: completeAccount, balanceMinor: -100000),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Partial'), findsNothing);
    expect(find.text('Not enough history'), findsNothing);
  });

  testWidgets('credit card appearance resolves saved and legacy identifiers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: const [
              CreditCardAppearanceBadge(
                iconId: 'rectangleStackFill',
                accentId: 'purple',
              ),
              CreditCardAppearanceBadge(
                iconId: 'unknownLegacyValue',
                accentId: 'unknownLegacyValue',
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byIcon(
        CreditCardAppearanceCatalog.iconFor('rectangleStackFill').icon,
      ),
      findsOneWidget,
    );
    expect(
      CreditCardAppearanceCatalog.iconFor('unknownLegacyValue').id,
      CreditCardAppearanceCatalog.defaultIconId,
    );
    expect(CreditCardAppearanceCatalog.accentFor('unknownLegacyValue'), isNull);
  });

  test('shared account appearance catalog is curated by account type', () {
    expect(
      AccountAppearanceCatalog.defaultIconIdFor(
        v2_account.AccountType.checking,
      ),
      'bank',
    );
    expect(
      AccountAppearanceCatalog.defaultIconIdFor(v2_account.AccountType.savings),
      'savings',
    );
    expect(
      AccountAppearanceCatalog.defaultIconIdFor(v2_account.AccountType.cash),
      'cash',
    );
    expect(
      AccountAppearanceCatalog.defaultIconIdFor(v2_account.AccountType.loan),
      'loanDocument',
    );
    expect(
      AccountAppearanceCatalog.iconsFor(v2_account.AccountType.checking),
      hasLength(7),
    );
    expect(
      AccountAppearanceCatalog.iconsFor(v2_account.AccountType.cash),
      hasLength(4),
    );
    expect(
      AccountAppearanceCatalog.iconsFor(v2_account.AccountType.loan),
      hasLength(4),
    );
    expect(AccountAppearanceCatalog.accents, hasLength(12));
    expect(
      AccountAppearanceCatalog.iconFor(
        v2_account.AccountType.loan,
        'unknownLegacyValue',
      ).id,
      'loanDocument',
    );
  });

  testWidgets('banking account appearance edits persist and render', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    final originalAccount = dataStore.accountById('checking');
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    final checkingCard = find.byWidgetPredicate(
      (widget) => widget is AccountCard && widget.account.id == 'checking',
    );
    await tester.ensureVisible(checkingCard);
    await tester.longPress(checkingCard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsWidgets);
    final iconRow = find.byKey(const ValueKey('account-icon-picker-row'));
    await tester.ensureVisible(iconRow);
    await tester.tap(iconRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-icon-portfolio')));
    await tester.pumpAndSettle();

    final accentRow = find.byKey(const ValueKey('account-accent-picker-row'));
    await tester.ensureVisible(accentRow);
    await tester.tap(accentRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-accent-gold')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final account = dataStore.accountById('checking');
    expect(account.appearanceIconId, 'portfolio');
    expect(account.appearanceAccentId, 'gold');
    expect(account.openingBalanceMinor, originalAccount.openingBalanceMinor);
    expect(account.type, originalAccount.type);
    expect(
      account.includeInGroupBalance,
      originalAccount.includeInGroupBalance,
    );
    expect(account.includeInNetWorth, originalAccount.includeInNetWorth);
    final portfolioIcon = AccountAppearanceCatalog.iconFor(
      v2_account.AccountType.checking,
      'portfolio',
    ).hugeIcon;
    expect(portfolioIcon, isNotNull);
    expect(
      find.descendant(
        of: checkingCard,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is HugeIcon && identical(widget.icon, portfolioIcon),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('new cash account uses its neutral type appearance by default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Pocket Cash');
    await tester.tap(find.text('Checking').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Cash').last);
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Cash'), findsWidgets);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final account = dataStore.accounts.singleWhere(
      (account) => account.name == 'Pocket Cash',
    );
    expect(account.type, v2_account.AccountType.cash);
    expect(account.appearanceIconId, 'cash');
    expect(account.appearanceAccentId, isNull);
  });

  test('credit utilization color thresholds use the unrounded ratio', () {
    expect(
      creditUtilizationFillColor(0, brightness: Brightness.light),
      AppColors.creditUtilizationHealthy,
    );
    expect(
      creditUtilizationFillColor(0.30, brightness: Brightness.light),
      AppColors.creditUtilizationHealthy,
    );
    expect(
      creditUtilizationFillColor(0.301, brightness: Brightness.light),
      AppColors.creditUtilizationModerate,
    );
    expect(
      creditUtilizationFillColor(0.699, brightness: Brightness.light),
      AppColors.creditUtilizationModerate,
    );
    expect(
      creditUtilizationFillColor(0.70, brightness: Brightness.light),
      AppColors.creditUtilizationHigh,
    );
  });

  testWidgets('Credit Insights shows placeholders when APR is unavailable', (
    tester,
  ) async {
    final account = v2_account.AccountRecord(
      id: 'credit-insights-without-apr',
      name: 'Credit Card',
      type: v2_account.AccountType.creditCard,
      openingBalanceMinor: 0,
      creditLimitMinor: 170000,
      interestEstimationEnabled: true,
      statementClosingDay: 15,
      sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountCard(account: account, balanceMinor: -113786),
        ),
      ),
    );

    expect(find.text('APR'), findsNothing);
    expect(find.text('Payment Due'), findsOneWidget);
    expect(find.text('Projected Statement'), findsOneWidget);
    expect(find.text('Estimated Interest'), findsOneWidget);
    // Payment Due has no configured day and Estimated Interest has no APR.
    // Projected Statement can still show the current recorded card balance.
    expect(find.text('–'), findsNWidgets(2));
  });

  testWidgets(
    'Credit Insights setup uses guidance and advances keyboard focus',
    (tester) async {
      final apr = TextEditingController();
      final statementDay = TextEditingController();
      final paymentDay = TextEditingController();
      addTearDown(apr.dispose);
      addTearDown(statementDay.dispose);
      addTearDown(paymentDay.dispose);
      var enabled = false;
      var disclosureAcknowledged = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CreditInsightsFormSection(
                enabled: enabled,
                disclosureAcknowledged: disclosureAcknowledged,
                onEnabledChanged: (value) => setState(() => enabled = value),
                onDisclosureAcknowledged: () =>
                    setState(() => disclosureAcknowledged = true),
                aprController: apr,
                statementClosingDayController: statementDay,
                paymentDueDayController: paymentDay,
                fieldValueStyle: Theme.of(context).textTheme.bodyLarge,
                fieldHintStyle: Theme.of(context).textTheme.bodyLarge,
                decoration: const InputDecoration(),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Enable Credit Insights'));
      await tester.pumpAndSettle();

      expect(find.text('About Credit Insights'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.byKey(const ValueKey('credit-insights-apr')), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('APR'), findsOneWidget);
      expect(find.text('Statement Closing Day'), findsOneWidget);
      expect(find.text('Payment Due Day'), findsOneWidget);
      expect(find.text('Enter APR (%)'), findsOneWidget);
      expect(find.text('Enter day (1–31)'), findsNWidgets(2));
      expect(find.text('29.99'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('credit-insights-apr')),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(find.text('Enter an APR'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(
                const ValueKey('credit-insights-statement-closing-day'),
              ),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('credit-insights-payment-due-day')),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('credit-insights-payment-due-day')),
            )
            .focusNode!
            .hasFocus,
        isFalse,
      );

      await tester.tap(find.byTooltip('About Credit Insights'));
      await tester.pumpAndSettle();
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enable Credit Insights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable Credit Insights'));
      await tester.pumpAndSettle();
      expect(find.text('About Credit Insights'), findsNothing);
      expect(find.byKey(const ValueKey('credit-insights-apr')), findsOneWidget);
    },
  );

  testWidgets('Credit Insights setup preserves existing saved values', (
    tester,
  ) async {
    final apr = TextEditingController(text: '28.49');
    final statementDay = TextEditingController(text: '15');
    final paymentDay = TextEditingController(text: '7');
    addTearDown(apr.dispose);
    addTearDown(statementDay.dispose);
    addTearDown(paymentDay.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => CreditInsightsFormSection(
              enabled: true,
              disclosureAcknowledged: true,
              onEnabledChanged: (_) {},
              onDisclosureAcknowledged: () {},
              aprController: apr,
              statementClosingDayController: statementDay,
              paymentDueDayController: paymentDay,
              fieldValueStyle: Theme.of(context).textTheme.bodyLarge,
              fieldHintStyle: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(),
            ),
          ),
        ),
      ),
    );

    expect(apr.text, '28.49');
    expect(statementDay.text, '15');
    expect(paymentDay.text, '7');
    expect(find.text('28.49'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('account long press can add expense for selected account', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.accounts,
          ),
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    final cashCard = find.byWidgetPredicate(
      (widget) => widget is AccountCard && widget.account.id == 'cash',
    );
    await tester.ensureVisible(cashCard);
    await tester.pumpAndSettle();
    await tester.longPress(cashCard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Expense'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('transaction-payee')),
      'Coffee',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '450',
    );
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final transaction = dataStore.transactions.singleWhere(
      (item) => item.payee == 'Coffee',
    );
    expect(transaction.accountId, 'cash');
    expect(transaction.amountMinor, 450);
    expect(transaction.type, v2_transaction.TransactionType.expense);
  });

  testWidgets('account long press can adjust balance with ledger entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.accounts,
          ),
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    final checkingCard = find.byWidgetPredicate(
      (widget) => widget is AccountCard && widget.account.id == 'checking',
    );
    await tester.ensureVisible(checkingCard);
    await tester.pumpAndSettle();
    await tester.longPress(checkingCard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust Balance'));
    await tester.pumpAndSettle();

    final adjustmentField = tester.widget<TextField>(
      find.byKey(const ValueKey('account-adjust-balance')),
    );
    expect(adjustmentField.autofocus, isTrue);
    expect(
      adjustmentField.keyboardType,
      const TextInputType.numberWithOptions(signed: true),
    );

    await tester.enterText(
      find.byKey(const ValueKey('account-adjust-balance')),
      '200000',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final adjustment = dataStore.transactions.last;
    expect(adjustment.type, v2_transaction.TransactionType.adjustment);
    expect(adjustment.accountId, 'checking');
    expect(dataStore.balanceForAccount('checking'), 200000);
  });

  testWidgets('account long press can archive account', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );

    final dataStore = FinanceDataStore(dataSet: dataSet);
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Checking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Checking'), findsNothing);
    expect(dataStore.accountById('checking').isArchived, isTrue);
  });

  testWidgets('account long press can delete account', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Checking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Checking'), findsNothing);
    expect(dataStore.accountById('checking').isDeleted, isTrue);
  });

  testWidgets('scheduled screen renders v2 scheduled rows', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final scheduledMonth = DateTime(now.year, now.month + 1);
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          scheduledTransactions: [
            rentSchedule(nextDate: scheduledMonth),
            scheduledExpense(
              id: 'sched-electric',
              payee: 'Electric',
              amountMinor: 14000,
              nextDate: scheduledMonth,
            ),
            scheduledExpense(
              id: 'sched-internet',
              payee: 'Internet',
              amountMinor: 7000,
              nextDate: DateTime(scheduledMonth.year, scheduledMonth.month, 15),
            ),
          ],
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();

    expect(find.text('Rent'), findsOneWidget);
    expect(find.byTooltip('Collapse calendar'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse calendar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand calendar'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand calendar'));
    await tester.pumpAndSettle();

    tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_right).first,
        )
        .onPressed!();
    await tester.pumpAndSettle();
    final initialMonth = scheduledMonth;
    final followingMonth = DateTime(initialMonth.year, initialMonth.month + 1);
    expect(find.text(_monthYearLabel(followingMonth)), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text(_monthYearLabel(initialMonth)), findsOneWidget);

    final scheduledFirst = find.byKey(
      ValueKey(
        'scheduled-calendar-day-${scheduledMonth.year}-${scheduledMonth.month}-1',
      ),
    );
    expect(
      find.descendant(of: scheduledFirst, matching: find.text('2')),
      findsOneWidget,
    );
    await tester.tap(scheduledFirst);
    await tester.pumpAndSettle();

    expect(
      find.text(ledgerFriendlyDayLabel(scheduledMonth, DateTime.now())),
      findsOneWidget,
    );
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Electric'), findsOneWidget);
    expect(find.text('Internet'), findsOneWidget);
    expect(find.text('Local alerts'), findsOneWidget);
  });

  testWidgets('scheduled calendar shows planned paid and remaining totals', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final followingMonth = DateTime(now.year, now.month + 2);
    final paidSchedule =
        scheduledExpense(
          id: 'sched-paid',
          payee: 'Planned card payment',
          amountMinor: 10000,
          nextDate: nextMonth,
        ).copyWith(
          frequency: v2_scheduled.RecurrenceFrequency.once,
          lastAction: v2_scheduled.ScheduledAction.paid,
          occurrences: [
            v2_scheduled.ScheduledOccurrenceRecord(
              scheduledDate: DateTime(month.year, month.month, 5),
              plannedAmountMinor: 10000,
              actualAmountMinor: 90000,
              actualPaymentDate: DateTime(month.year, month.month, 6),
              transactionId: 'paid-actual',
              status: v2_scheduled.ScheduledOccurrenceStatus.paid,
            ),
          ],
          sync: v2_sync.SyncMetadata.fresh().deleted(),
        );
    final skippedSchedule =
        scheduledExpense(
          id: 'sched-skipped',
          payee: 'Skipped bill',
          amountMinor: 10000,
          nextDate: nextMonth,
        ).copyWith(
          frequency: v2_scheduled.RecurrenceFrequency.once,
          lastAction: v2_scheduled.ScheduledAction.skipped,
          occurrences: [
            v2_scheduled.ScheduledOccurrenceRecord(
              scheduledDate: DateTime(month.year, month.month, 11),
              plannedAmountMinor: 10000,
              status: v2_scheduled.ScheduledOccurrenceStatus.skipped,
            ),
          ],
          sync: v2_sync.SyncMetadata.fresh().deleted(),
        );
    v2_scheduled.ScheduledTransactionRecord once(
      v2_scheduled.ScheduledTransactionRecord item,
    ) => item.copyWith(frequency: v2_scheduled.RecurrenceFrequency.once);
    final schedules = [
      paidSchedule,
      skippedSchedule,
      once(
        scheduledExpense(
          id: 'sched-unpaid',
          payee: 'Unpaid bill',
          amountMinor: 2000000,
          nextDate: DateTime(month.year, month.month, 10),
        ),
      ),
      once(
        scheduledExpense(
          id: 'sched-income',
          payee: 'Paycheck',
          amountMinor: 50000,
          nextDate: DateTime(month.year, month.month, 14),
        ).copyWith(type: v2_transaction.TransactionType.income),
      ),
      once(
        scheduledExpense(
          id: 'sched-mixed-expense',
          payee: 'Mixed expense',
          amountMinor: 10000,
          nextDate: DateTime(month.year, month.month, 14),
        ),
      ),
      once(
        scheduledExpense(
          id: 'sched-apple',
          payee: 'Apple',
          amountMinor: 999,
          nextDate: DateTime(month.year, month.month, 15),
        ),
      ),
      once(
        scheduledExpense(
          id: 'sched-netflix',
          payee: 'Netflix',
          amountMinor: 2167,
          nextDate: DateTime(month.year, month.month, 15),
        ),
      ),
      once(
        scheduledExpense(
          id: 'sched-transfer',
          payee: 'Savings transfer',
          amountMinor: 30000,
          nextDate: DateTime(month.year, month.month, 12),
        ).copyWith(
          type: v2_transaction.TransactionType.transfer,
          transferAccountId: 'cash',
          clearCategory: true,
        ),
      ),
      scheduledExpense(
        id: 'sched-next-month',
        payee: 'Next month only',
        amountMinor: 7700,
        nextDate: DateTime(nextMonth.year, nextMonth.month, 8),
      ),
    ];
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        scheduledTransactions: schedules,
        transactions: [
          ...migrated.transactions,
          v2_transaction.TransactionRecord(
            id: 'paid-actual',
            type: v2_transaction.TransactionType.expense,
            accountId: 'checking',
            categoryId: 'dining',
            date: DateTime(month.year, month.month, 6),
            payee: 'Planned card payment',
            amountMinor: 90000,
            scheduledTransactionId: 'sched-paid',
            scheduledOccurrenceDate: DateTime(month.year, month.month, 5),
            scheduledPlannedAmountMinor: 10000,
            sync: v2_sync.SyncMetadata.fresh(),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$21,131.66',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-paid')))
          .data,
      r'$900.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-remaining')))
          .data,
      r'$20,931.66',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('scheduled-month-completed-label')),
          )
          .data,
      'Completed',
    );

    final expenseDay = find.byKey(
      ValueKey('scheduled-calendar-day-${month.year}-${month.month}-5'),
    );
    expect(
      find.descendant(
        of: expenseDay,
        matching: find.byKey(const ValueKey('calendar-activity-dots')),
      ),
      findsNothing,
    );
    await selectScheduledCalendarFilter(tester, 'expenses');
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('scheduled-month-completed-label')),
          )
          .data,
      'Paid',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$20,331.66',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-paid')))
          .data,
      r'$900.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-remaining')))
          .data,
      r'$20,131.66',
    );
    expect(
      find.byKey(
        ValueKey('calendar-filtered-total-${month.year}-${month.month}-5'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey('calendar-filtered-total-${month.year}-${month.month}-10'),
        ),
        matching: find.text(r'-$20,000.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey('calendar-filtered-total-${month.year}-${month.month}-15'),
        ),
        matching: find.text(r'-$31.66'),
      ),
      findsOneWidget,
    );

    Future<void> expectSummaryForFilter({
      required String filter,
      required String completedLabel,
      required String planned,
      required String completed,
      required String remaining,
    }) async {
      await selectScheduledCalendarFilter(tester, filter);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('scheduled-month-completed-label')),
            )
            .data,
        completedLabel,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
            .data,
        planned,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('scheduled-month-paid')))
            .data,
        completed,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('scheduled-month-remaining')),
            )
            .data,
        remaining,
      );
    }

    await expectSummaryForFilter(
      filter: 'income',
      completedLabel: 'Received',
      planned: r'$500.00',
      completed: r'$0.00',
      remaining: r'$500.00',
    );
    await expectSummaryForFilter(
      filter: 'transfers',
      completedLabel: 'Completed',
      planned: r'$300.00',
      completed: r'$0.00',
      remaining: r'$300.00',
    );
    await expectSummaryForFilter(
      filter: 'goals',
      completedLabel: 'Funded',
      planned: r'$0.00',
      completed: r'$0.00',
      remaining: r'$0.00',
    );
    await selectScheduledCalendarFilter(tester, 'expenses');

    final ordinaryDecoration = tester.widget<DecoratedBox>(
      find.byKey(
        ValueKey(
          'scheduled-calendar-selection-${month.year}-${month.month}-15',
        ),
      ),
    );
    expect((ordinaryDecoration.decoration as BoxDecoration).color, isNull);
    expect((ordinaryDecoration.decoration as BoxDecoration).border, isNull);
    final pageScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(pageScroll.position.pixels, 0);
    final scheduledDay = find.byKey(
      ValueKey('scheduled-calendar-day-${month.year}-${month.month}-15'),
    );
    final expenseDayRect = tester.getRect(scheduledDay);
    await tester.tapAt(
      Offset(expenseDayRect.left + 1, expenseDayRect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(pageScroll.position.pixels, greaterThan(0));
    final selectedDecoration = tester.widget<DecoratedBox>(
      find.byKey(
        ValueKey(
          'scheduled-calendar-selection-${month.year}-${month.month}-15',
        ),
      ),
    );
    expect((selectedDecoration.decoration as BoxDecoration).color, isNotNull);
    expect((selectedDecoration.decoration as BoxDecoration).border, isNotNull);
    expect(find.text('Apple'), findsWidgets);
    expect(find.text('Netflix'), findsWidgets);
    expect(
      find.textContaining('No Expense scheduled activity on'),
      findsNothing,
    );

    tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_right).first,
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$77.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-remaining')))
          .data,
      r'$77.00',
    );
    expect(find.text('Next month only'), findsOneWidget);
    expect(find.textContaining('No scheduled transactions in'), findsNothing);

    tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_right).first,
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Next month only'), findsOneWidget);
    expect(find.textContaining('No scheduled transactions in'), findsNothing);
    pageScroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey(
          'scheduled-calendar-day-${followingMonth.year}-${followingMonth.month}-8',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pageScroll.position.pixels, greaterThan(0));
  });

  test(
    'scheduled monthly summary is type-aware and credits partial payment',
    () {
      final expenseDate = DateTime(2026, 8, 11);
      final incomeDate = DateTime(2026, 8, 12);
      final transferDate = DateTime(2026, 8, 13);
      final skippedDate = DateTime(2026, 8, 14);
      final expense =
          scheduledExpense(
            id: 'summary-expense',
            payee: 'Expense',
            amountMinor: 10000,
            nextDate: expenseDate,
          ).copyWith(
            occurrences: [
              v2_scheduled.ScheduledOccurrenceRecord(
                scheduledDate: expenseDate,
                plannedAmountMinor: 10000,
                status: v2_scheduled.ScheduledOccurrenceStatus.paid,
                actualAmountMinor: 15000,
                transactionId: 'summary-expense-actual',
              ),
            ],
          );
      final income = scheduledExpense(
        id: 'summary-income',
        payee: 'Income',
        amountMinor: 20000,
        nextDate: incomeDate,
      ).copyWith(type: v2_transaction.TransactionType.income);
      final transfer =
          scheduledExpense(
            id: 'summary-transfer',
            payee: 'Transfer',
            amountMinor: 90000,
            nextDate: transferDate,
          ).copyWith(
            type: v2_transaction.TransactionType.transfer,
            transferAccountId: 'savings',
            clearCategory: true,
            occurrences: [
              v2_scheduled.ScheduledOccurrenceRecord(
                scheduledDate: transferDate,
                plannedAmountMinor: 90000,
                status: v2_scheduled.ScheduledOccurrenceStatus.paid,
                actualAmountMinor: 64160,
                transactionId: 'summary-transfer-actual',
              ),
            ],
          );
      final skipped =
          scheduledExpense(
            id: 'summary-skipped',
            payee: 'Skipped',
            amountMinor: 5000,
            nextDate: skippedDate,
          ).copyWith(
            occurrences: [
              v2_scheduled.ScheduledOccurrenceRecord(
                scheduledDate: skippedDate,
                plannedAmountMinor: 5000,
                status: v2_scheduled.ScheduledOccurrenceStatus.skipped,
              ),
            ],
          );
      final occurrences = [
        ScheduledCalendarOccurrence(
          transaction: expense,
          scheduledDate: expenseDate,
          plannedAmountMinor: 10000,
          record: expense.occurrences.single,
        ),
        ScheduledCalendarOccurrence(
          transaction: income,
          scheduledDate: incomeDate,
          plannedAmountMinor: 20000,
        ),
        ScheduledCalendarOccurrence(
          transaction: transfer,
          scheduledDate: transferDate,
          plannedAmountMinor: 90000,
          record: transfer.occurrences.single,
        ),
        ScheduledCalendarOccurrence(
          transaction: skipped,
          scheduledDate: skippedDate,
          plannedAmountMinor: 5000,
          record: skipped.occurrences.single,
        ),
      ];
      final transactions = [
        v2_transaction.TransactionRecord(
          id: 'summary-expense-actual',
          type: v2_transaction.TransactionType.expense,
          accountId: 'checking',
          categoryId: 'dining',
          date: expenseDate,
          payee: 'Expense',
          amountMinor: 15000,
          scheduledTransactionId: expense.id,
          scheduledOccurrenceDate: expenseDate,
          scheduledPlannedAmountMinor: 10000,
          sync: v2_sync.SyncMetadata.fresh(),
        ),
        v2_transaction.TransactionRecord(
          id: 'summary-transfer-actual',
          type: v2_transaction.TransactionType.transfer,
          accountId: 'checking',
          transferAccountId: 'savings',
          date: transferDate,
          payee: 'Transfer',
          amountMinor: 64160,
          scheduledTransactionId: transfer.id,
          scheduledOccurrenceDate: transferDate,
          scheduledPlannedAmountMinor: 90000,
          sync: v2_sync.SyncMetadata.fresh(),
        ),
      ];

      ScheduledMonthSummary summary(CalendarActivityFilter filter) =>
          scheduledMonthSummary(occurrences, transactions, filter: filter);

      expect(
        summary(CalendarActivityFilter.expenses).plannedAmountMinor,
        15000,
      );
      expect(summary(CalendarActivityFilter.expenses).paidAmountMinor, 15000);
      expect(summary(CalendarActivityFilter.expenses).remainingAmountMinor, 0);
      expect(summary(CalendarActivityFilter.income).plannedAmountMinor, 20000);
      expect(summary(CalendarActivityFilter.income).paidAmountMinor, 0);
      expect(
        summary(CalendarActivityFilter.income).remainingAmountMinor,
        20000,
      );
      expect(
        summary(CalendarActivityFilter.transfers).plannedAmountMinor,
        90000,
      );
      expect(summary(CalendarActivityFilter.transfers).paidAmountMinor, 64160);
      expect(
        summary(CalendarActivityFilter.transfers).remainingAmountMinor,
        25840,
      );
      expect(summary(CalendarActivityFilter.goals).plannedAmountMinor, 0);
      expect(summary(CalendarActivityFilter.all).plannedAmountMinor, 125000);
      expect(summary(CalendarActivityFilter.all).paidAmountMinor, 79160);
      expect(summary(CalendarActivityFilter.all).remainingAmountMinor, 45840);

      expect(CalendarActivityFilter.all.scheduledCompletedLabel, 'Completed');
      expect(CalendarActivityFilter.income.scheduledCompletedLabel, 'Received');
      expect(CalendarActivityFilter.expenses.scheduledCompletedLabel, 'Paid');
      expect(
        CalendarActivityFilter.transfers.scheduledCompletedLabel,
        'Completed',
      );
      expect(CalendarActivityFilter.goals.scheduledCompletedLabel, 'Funded');
    },
  );

  testWidgets('Scheduled page excludes ordinary ledger activity', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final today = DateTime.now();
    v2_transaction.TransactionRecord activity({
      required String id,
      required String payee,
      required v2_transaction.TransactionType type,
      required int amountMinor,
      String? transferAccountId,
    }) {
      return v2_transaction.TransactionRecord(
        id: id,
        type: type,
        accountId: 'checking',
        transferAccountId: transferAccountId,
        categoryId: type == v2_transaction.TransactionType.transfer
            ? null
            : 'dining',
        date: today,
        payee: payee,
        amountMinor: amountMinor,
        sync: v2_sync.SyncMetadata.fresh(),
      );
    }

    final schedules = [
      scheduledExpense(
        id: 'calendar-scheduled-income',
        payee: 'Scheduled Income',
        amountMinor: 2000000,
        nextDate: today,
      ).copyWith(
        type: v2_transaction.TransactionType.income,
        frequency: v2_scheduled.RecurrenceFrequency.once,
      ),
      scheduledExpense(
        id: 'calendar-scheduled-expense',
        payee: 'Scheduled Expense',
        amountMinor: 10000000,
        nextDate: today,
      ).copyWith(frequency: v2_scheduled.RecurrenceFrequency.once),
      scheduledExpense(
        id: 'calendar-scheduled-transfer',
        payee: 'Scheduled Transfer',
        amountMinor: 500000,
        nextDate: today,
      ).copyWith(
        type: v2_transaction.TransactionType.transfer,
        transferAccountId: 'cash',
        clearCategory: true,
        frequency: v2_scheduled.RecurrenceFrequency.once,
      ),
    ];
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        scheduledTransactions: schedules,
        transactions: [
          ...migrated.transactions,
          activity(
            id: 'calendar-income',
            payee: 'Calendar Income',
            type: v2_transaction.TransactionType.income,
            amountMinor: 2000000,
          ),
          activity(
            id: 'calendar-expense',
            payee: 'Calendar Expense',
            type: v2_transaction.TransactionType.expense,
            amountMinor: 10000000,
          ),
          activity(
            id: 'calendar-transfer',
            payee: 'Calendar Transfer',
            type: v2_transaction.TransactionType.transfer,
            amountMinor: 500000,
            transferAccountId: 'cash',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();

    expect(find.text('Calendar Income'), findsNothing);
    expect(find.text('Calendar Expense'), findsNothing);
    expect(find.text('Calendar Transfer'), findsNothing);
    expect(find.text('Scheduled Income'), findsWidgets);
    expect(find.text('Scheduled Expense'), findsWidgets);
    expect(find.text('Scheduled Transfer'), findsWidgets);
    expect(find.byKey(const ValueKey('calendar-activity-dots')), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey(
            'scheduled-calendar-day-${today.year}-${today.month}-${today.day}',
          ),
        ),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    await selectScheduledCalendarFilter(tester, 'income');
    expect(find.text('Scheduled Income'), findsWidgets);
    expect(find.text('Scheduled Expense'), findsNothing);
    expect(find.text('Scheduled Transfer'), findsNothing);
    expect(find.text(r'$20,000.00'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$20,000.00',
    );

    await selectScheduledCalendarFilter(tester, 'expenses');
    expect(find.text('Scheduled Income'), findsNothing);
    expect(find.text('Scheduled Expense'), findsWidgets);
    expect(find.text('Scheduled Transfer'), findsNothing);
    expect(find.text(r'-$100,000.00'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$100,000.00',
    );

    await selectScheduledCalendarFilter(tester, 'transfers');
    expect(find.text('Scheduled Transfer'), findsWidgets);
    expect(find.text(r'$5,000.00'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$5,000.00',
    );

    await selectScheduledCalendarFilter(tester, 'goals');
    expect(find.text('Scheduled Income'), findsNothing);
    expect(find.text('Scheduled Expense'), findsNothing);
    expect(find.text('Scheduled Transfer'), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-filter-empty-state')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$0.00',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar cell preserves full large filtered currency values', (
    tester,
  ) async {
    const amounts = [99, 10000, 999999, 2000000, 10000000, -2000000];
    for (final amount in amounts) {
      final scheduled =
          scheduledExpense(
            id: 'amount-$amount',
            payee: 'Amount',
            amountMinor: amount.abs(),
            nextDate: DateTime(2026, 7, 24),
          ).copyWith(
            type: amount < 0
                ? v2_transaction.TransactionType.expense
                : v2_transaction.TransactionType.income,
          );
      final occurrence = ScheduledCalendarOccurrence(
        transaction: scheduled,
        scheduledDate: scheduled.nextDate,
        plannedAmountMinor: scheduled.amountMinor,
      );
      final filter = amount < 0
          ? CalendarActivityFilter.expenses
          : CalendarActivityFilter.income;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 58,
                child: ScheduledCalendarDayCell(
                  day: 24,
                  month: DateTime(2026, 7),
                  activitySummary: CalendarDayActivitySummary([
                    CalendarDayActivity.scheduled(occurrence),
                  ]),
                  activityFilter: filter,
                  currency: const UserPreferences().currency,
                  isSelected: false,
                  isToday: false,
                  onSelectDate: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final expected = MoneyFormatter(
        const UserPreferences().currency,
      ).formatMinor(amount);
      expect(find.text(expected), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('calendar edge badges stay inside Sunday and Saturday cells', (
    tester,
  ) async {
    final month = DateTime(2026, 8);
    ScheduledCalendarOccurrence occurrence(int day, int index) {
      final scheduled = scheduledExpense(
        id: 'edge-$day-$index',
        payee: 'Edge',
        amountMinor: 10000000,
        nextDate: DateTime(2026, 8, day),
      );
      return ScheduledCalendarOccurrence(
        transaction: scheduled,
        scheduledDate: scheduled.nextDate,
        plannedAmountMinor: scheduled.amountMinor,
      );
    }

    final sundayActivities = [CalendarDayActivity.scheduled(occurrence(2, 0))];
    final saturdayActivities = [
      for (var index = 0; index < 123; index++)
        CalendarDayActivity.scheduled(occurrence(8, index)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: ScheduledCalendarGrid(
                month: month,
                activitySummaryByDay: {
                  calendarDateKey(DateTime(2026, 8, 2)):
                      CalendarDayActivitySummary(sundayActivities),
                  calendarDateKey(DateTime(2026, 8, 8)):
                      CalendarDayActivitySummary(saturdayActivities),
                },
                activityFilter: CalendarActivityFilter.expenses,
                currency: const UserPreferences().currency,
                selectedDate: DateTime(2026, 8, 8),
                onSelectDate: (_) {},
                onActivityFilterChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    for (final day in const [2, 8]) {
      final cell = find.byKey(ValueKey('scheduled-calendar-day-2026-8-$day'));
      final badge = find.byKey(
        ValueKey('scheduled-calendar-count-2026-8-$day'),
      );
      expect(cell, findsOneWidget);
      expect(badge, findsOneWidget);
      final cellRect = tester.getRect(cell);
      final badgeRect = tester.getRect(badge);
      expect(badgeRect.left, greaterThanOrEqualTo(cellRect.left));
      expect(badgeRect.right, lessThanOrEqualTo(cellRect.right));
      expect(badgeRect.top, greaterThanOrEqualTo(cellRect.top));
      expect(badgeRect.bottom, lessThanOrEqualTo(cellRect.bottom));
    }
    expect(find.text('1'), findsWidgets);
    expect(find.text('123'), findsOneWidget);
    expect(find.text(r'-$100,000.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('calendar aggregation uses one canonical local date key', () {
    final august = DateTime(2026, 8);
    v2_transaction.TransactionRecord transaction({
      required String id,
      required v2_transaction.TransactionType type,
      required DateTime date,
      required int amountMinor,
      String? transferAccountId,
    }) {
      return v2_transaction.TransactionRecord(
        id: id,
        type: type,
        accountId: 'checking',
        transferAccountId: transferAccountId,
        categoryId: type == v2_transaction.TransactionType.transfer
            ? null
            : 'dining',
        date: date,
        payee: id,
        amountMinor: amountMinor,
        sync: v2_sync.SyncMetadata.fresh(),
      );
    }

    final utcNearMidnight = DateTime.utc(2026, 8, 16, 1, 30);
    expect(calendarDateKey(utcNearMidnight), DateTime(2026, 8, 15));

    final actual = [
      transaction(
        id: 'actual-income-aug-10',
        type: v2_transaction.TransactionType.income,
        date: DateTime(2026, 8, 10),
        amountMinor: 10000,
      ),
      transaction(
        id: 'actual-expense-aug-11',
        type: v2_transaction.TransactionType.expense,
        date: DateTime(2026, 8, 11),
        amountMinor: 11000,
      ),
      transaction(
        id: 'actual-transfer-aug-12',
        type: v2_transaction.TransactionType.transfer,
        date: DateTime(2026, 8, 12),
        amountMinor: 12000,
        transferAccountId: 'savings',
      ),
      transaction(
        id: 'actual-near-midnight-aug-14',
        type: v2_transaction.TransactionType.expense,
        date: DateTime(2026, 8, 14, 23, 59, 59),
        amountMinor: 14000,
      ),
      transaction(
        id: 'actual-utc-local-aug-15',
        type: v2_transaction.TransactionType.income,
        date: utcNearMidnight,
        amountMinor: 15000,
      ),
      transaction(
        id: 'actual-month-end-aug-31',
        type: v2_transaction.TransactionType.expense,
        date: DateTime(2026, 8, 31, 23, 59),
        amountMinor: 31000,
      ),
      transaction(
        id: 'actual-next-month-sep-1',
        type: v2_transaction.TransactionType.income,
        date: DateTime(2026, 9),
        amountMinor: 100,
      ),
    ];
    final goal = GoalRecord(
      id: 'goal-calendar-aug',
      name: 'Calendar Goal',
      targetAmountMinor: 100000,
      status: GoalStatus.active,
      fundingMethod: GoalFundingMethod.accountFunded,
      defaultFundingAccountId: 'checking',
      sync: v2_sync.SyncMetadata.fresh(),
    );
    final funding = GoalFundingEventRecord(
      id: 'goal-funding-aug-13',
      sourceAccountId: 'checking',
      totalAmountMinor: 13000,
      date: DateTime(2026, 8, 13),
      allocations: const [
        GoalFundingAllocation(
          id: 'goal-allocation-aug-13',
          fundingEventId: 'goal-funding-aug-13',
          goalId: 'goal-calendar-aug',
          amountMinor: 13000,
          order: 0,
        ),
      ],
      sync: v2_sync.SyncMetadata.fresh(),
    );
    final goals = goalCalendarActivitiesForMonth(
      [goal],
      const [],
      [funding],
      august,
    );
    final actualActivities = calendarActualActivitiesForMonth(
      actual,
      goals,
      august,
    );
    final scheduled = [
      scheduledExpense(
        id: 'scheduled-expense-aug-21',
        payee: 'August 21 bill',
        amountMinor: 21000,
        nextDate: DateTime(2026, 8, 21),
      ).copyWith(frequency: v2_scheduled.RecurrenceFrequency.once),
      scheduledExpense(
        id: 'scheduled-expense-aug-22',
        payee: 'August 22 bill',
        amountMinor: 22000,
        nextDate: DateTime(2026, 8, 22),
      ).copyWith(frequency: v2_scheduled.RecurrenceFrequency.once),
    ];
    final projected = scheduledOccurrencesForMonth(scheduled, august);
    final combined = scheduledCalendarActivities(projected);
    final byDate = calendarActivitySummaryByDay(combined);

    expect(
      actualActivities
          .where((item) => item.transaction != null)
          .map((item) => item.transaction!.id),
      containsAll([
        'actual-income-aug-10',
        'actual-expense-aug-11',
        'actual-transfer-aug-12',
        'actual-near-midnight-aug-14',
        'actual-utc-local-aug-15',
        'actual-month-end-aug-31',
      ]),
    );
    expect(
      actualActivities.map((item) => item.transaction?.id),
      isNot(contains('actual-next-month-sep-1')),
    );
    expect(byDate[DateTime(2026, 8, 10)], isNull);
    expect(byDate[DateTime(2026, 8, 11)], isNull);
    expect(byDate[DateTime(2026, 8, 12)], isNull);
    expect(byDate[DateTime(2026, 8, 13)], isNull);
    expect(byDate[DateTime(2026, 8, 14)], isNull);
    expect(byDate[DateTime(2026, 8, 15)], isNull);
    expect(
      byDate[DateTime(2026, 8, 21)]!.countFor(CalendarActivityFilter.expenses),
      1,
    );
    expect(
      byDate[DateTime(2026, 8, 22)]!.countFor(CalendarActivityFilter.expenses),
      1,
    );
    expect(byDate[DateTime(2026, 8, 31)], isNull);
    expect(byDate[DateTime(2026, 9)], isNull);
    expect(
      combined.every((activity) => activity.scheduledOccurrence != null),
      isTrue,
    );
  });

  testWidgets('dashboard shows scheduled due count', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          scheduledTransactions: [
            rentSchedule(
              nextDate: DateTime.now().subtract(const Duration(days: 1)),
            ),
          ],
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    expect(find.text('Next Scheduled'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
  });

  testWidgets('dashboard excludes resolved and orphaned scheduled records', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final today = DateTime.now();
    final future = DateTime(today.year, today.month + 1, 21);
    final resolved = rentSchedule(nextDate: future).copyWith(
      frequency: v2_scheduled.RecurrenceFrequency.once,
      occurrences: [
        v2_scheduled.ScheduledOccurrenceRecord(
          scheduledDate: future,
          plannedAmountMinor: 90000,
          status: v2_scheduled.ScheduledOccurrenceStatus.paid,
        ),
      ],
    );
    final orphaned = scheduledExpense(
      id: 'sched-gina',
      payee: 'Gina',
      amountMinor: 60000,
      nextDate: future,
    ).copyWith(accountId: 'missing-account');
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(
          dataSet: migrated.copyWith(
            scheduledTransactions: [resolved, orphaned],
          ),
        ),
      ),
    );

    expect(find.text('Next Scheduled'), findsOneWidget);
    expect(find.text('Gina'), findsNothing);
    expect(find.text('Rent'), findsNothing);
    expect(find.text('No scheduled transactions'), findsOneWidget);
  });

  testWidgets('scheduled summary excludes orphaned pending projections', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final projectedMonth = DateTime(now.year, now.month + 1);
    final orphaned = scheduledExpense(
      id: 'sched-orphaned-summary',
      payee: 'Gina',
      amountMinor: 60000,
      nextDate: DateTime(projectedMonth.year, projectedMonth.month, 21),
    ).copyWith(accountId: 'deleted-account');
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(
          dataSet: migrated.copyWith(scheduledTransactions: [orphaned]),
        ),
      ),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_right).first,
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Gina'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$0.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-remaining')))
          .data,
      r'$0.00',
    );
  });

  testWidgets(
    'reset scheduled history requires confirmation and refreshes UI',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final occurrenceDate = DateTime(2026, 7, 1);
      final schedule = rentSchedule(nextDate: DateTime(2026, 8, 1)).copyWith(
        occurrences: [
          v2_scheduled.ScheduledOccurrenceRecord(
            scheduledDate: occurrenceDate,
            plannedAmountMinor: 90000,
            status: v2_scheduled.ScheduledOccurrenceStatus.paid,
            actualAmountMinor: 95000,
            actualPaymentDate: occurrenceDate,
            transactionId: 'scheduled-ledger',
          ),
        ],
      );
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final linkedTransaction = migrated.transactions.first.copyWith(
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: occurrenceDate,
        scheduledPlannedAmountMinor: 90000,
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          transactions: [linkedTransaction, ...migrated.transactions.skip(1)],
          scheduledTransactions: [schedule],
        ),
      );
      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final dataManagementRow = find.byKey(
        const ValueKey('data-management-row'),
      );
      await tester.ensureVisible(dataManagementRow);
      await tester.pumpAndSettle();
      await tester.tap(dataManagementRow);
      await tester.pumpAndSettle();
      final resetRow = find.text('Reset Scheduled Calendar History');
      await tester.ensureVisible(resetRow);
      await tester.pumpAndSettle();
      await tester.tap(resetRow.hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Reset Scheduled Calendar History?'), findsOneWidget);
      expect(find.text('Reset History'), findsOneWidget);
      expect(dataStore.scheduledTransactions.single.occurrences, hasLength(1));

      await tester.tap(
        find.byKey(const ValueKey('cancel-scheduled-history-reset')),
      );
      await tester.pumpAndSettle();
      expect(dataStore.scheduledTransactions.single.occurrences, hasLength(1));

      await tester.tap(resetRow);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-scheduled-history-reset')),
      );
      await tester.pumpAndSettle();

      expect(dataStore.scheduledTransactions, hasLength(1));
      expect(dataStore.scheduledTransactions.single.occurrences, isEmpty);
      expect(dataStore.transactions, hasLength(migrated.transactions.length));
      expect(dataStore.transactions.first.scheduledTransactionId, isNull);
      final julySummary = scheduledMonthSummary(
        scheduledOccurrencesForMonth(
          dataStore.scheduledTransactions,
          DateTime(2026, 7),
        ),
        dataStore.transactions,
      );
      expect(julySummary.plannedAmountMinor, 0);
      expect(julySummary.paidAmountMinor, 0);
      expect(julySummary.remainingAmountMinor, 0);
      expect(find.text('Scheduled calendar history reset'), findsOneWidget);
    },
  );

  testWidgets('scheduled details uses polished sheet and edit still opens', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          scheduledTransactions: [
            rentSchedule(nextDate: DateTime(now.year, now.month, now.day)),
          ],
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();

    expect(find.text('Scheduled Transaction'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scheduled-detail-payee')),
      findsOneWidget,
    );
    expect(find.text('Scheduled amount'), findsOneWidget);
    expect(find.text('Mark as Paid'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Scheduled Transaction'), findsOneWidget);
  });

  testWidgets(
    'scheduled occurrences share date cards and calendar highlights the card',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day);
      final dataSet = const V1SnapshotMigrator()
          .migrate(legacyStore.snapshot().toJson())
          .copyWith(
            scheduledTransactions: [
              rentSchedule(nextDate: date),
              scheduledExpense(
                id: 'sched-utilities',
                payee: 'Utilities',
                amountMinor: 12500,
                nextDate: date,
              ),
            ],
          );

      await tester.pumpWidget(
        MoneyTallyApp(
          store: legacyStore,
          dataStore: FinanceDataStore(dataSet: dataSet),
        ),
      );
      await tester.tap(find.text('Scheduled').last);
      await tester.pumpAndSettle();

      final cardKey = ValueKey('scheduled-day-card-${calendarDateId(date)}');
      final card = find.byKey(cardKey);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Rent')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Utilities')),
        findsOneWidget,
      );

      final initialDecoration =
          tester.widget<AnimatedContainer>(card).decoration as BoxDecoration;
      final calendarDay = find.byKey(
        ValueKey(
          'scheduled-calendar-day-${date.year}-${date.month}-${date.day}',
        ),
      );
      await tester.ensureVisible(calendarDay);
      await tester.pumpAndSettle();
      await tester.tap(calendarDay.hitTestable());
      await tester.pump(const Duration(milliseconds: 260));
      final highlightedDecoration =
          tester.widget<AnimatedContainer>(card).decoration as BoxDecoration;
      expect(highlightedDecoration.color, isNot(initialDecoration.color));
      for (final scheduleId in ['sched-rent', 'sched-utilities']) {
        final marker = tester.widget<AnimatedContainer>(
          find.byKey(
            ValueKey(
              'scheduled-occurrence-marker-$scheduleId-${calendarDateId(date)}',
            ),
          ),
        );
        expect(marker.constraints?.maxWidth, 0);
      }

      await tester.pump(const Duration(milliseconds: 1600));
      expect(
        tester.widget<AnimatedContainer>(card).duration,
        const Duration(milliseconds: 650),
      );
      await tester.pump(const Duration(milliseconds: 700));
      final restoredDecoration =
          tester.widget<AnimatedContainer>(card).decoration as BoxDecoration;
      expect(restoredDecoration.color, initialDecoration.color);
    },
  );

  testWidgets('scheduled edit loads splits and requires amount rebalance', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final schedule =
        rentSchedule(nextDate: DateTime(now.year, now.month, now.day)).copyWith(
          note: 'Keep this note',
          alertPreference: v2_scheduled.AlertPreference.threeDaysBefore,
          customAlertTimeMinutes: 8 * 60 + 30,
          splitLines: const [
            v2_transaction.TransactionSplitLine(
              id: 'rent-dining',
              categoryId: 'dining',
              amountMinor: 60000,
            ),
            v2_transaction.TransactionSplitLine(
              id: 'rent-snacks',
              categoryId: 'snacks',
              amountMinor: 30000,
            ),
          ],
        );
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(scheduledTransactions: [schedule]),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Split Categories'), findsOneWidget);
    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('Snacks'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-amount')),
      '1000.00',
    );
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    final splitSection = find.byKey(
      const ValueKey('scheduled-split-category-field'),
    );
    final splitAmounts = find.descendant(
      of: splitSection,
      matching: find.byType(TextField),
    );
    await tester.enterText(splitAmounts.at(0), '70000');
    await tester.pumpAndSettle();
    expect(find.text('Balanced'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(dataStore.scheduledTransactions, hasLength(1));
    final updated = dataStore.scheduledTransactions.single;
    expect(updated.id, schedule.id);
    expect(updated.amountMinor, 100000);
    expect(updated.splitLines.map((line) => line.amountMinor), [70000, 30000]);
    expect(updated.note, 'Keep this note');
    expect(
      updated.alertPreference,
      v2_scheduled.AlertPreference.threeDaysBefore,
    );
    expect(updated.customAlertTimeMinutes, 8 * 60 + 30);
  });

  testWidgets('scheduled edit can create and select a required category', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final schedule = rentSchedule(
      nextDate: DateTime(now.year, now.month, now.day),
    ).copyWith(clearCategory: true);
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(scheduledTransactions: [schedule]),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Edit'));
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('scheduled-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add New Category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-new-category-name')),
      'Scheduled Bills',
    );
    await tester.tap(
      find.byKey(const ValueKey('transaction-save-new-category')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('transaction-new-category-name')),
      findsNothing,
    );
    expect(find.text('Scheduled Bills'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final updated = dataStore.scheduledTransactions.single;
    expect(dataStore.categoryById(updated.categoryId!).name, 'Scheduled Bills');
  });

  testWidgets('mark paid can repair a missing category and retain it', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final dueDate = DateTime(now.year, now.month, now.day);
    final schedule = rentSchedule(
      nextDate: dueDate,
    ).copyWith(clearCategory: true);
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(scheduledTransactions: [schedule]),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Paid'));
    await tester.pumpAndSettle();

    final confirm = find.widgetWithText(FilledButton, 'Confirm');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('mark-paid-category')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mark-paid-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add New Category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-new-category-name')),
      'Payment Category',
    );
    await tester.tap(
      find.byKey(const ValueKey('transaction-save-new-category')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('transaction-new-category-name')),
      findsNothing,
    );
    expect(find.text('Payment Category'), findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    final paid = dataStore.transactions.singleWhere(
      (transaction) => transaction.scheduledTransactionId == schedule.id,
    );
    final updated = dataStore.scheduledTransactions.single;
    expect(dataStore.categoryById(paid.categoryId!).name, 'Payment Category');
    expect(updated.categoryId, paid.categoryId);
  });

  testWidgets('projected scheduled occurrence supports details and mark paid', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final originalNextDate = DateTime(now.year, now.month - 1, 7);
    final projectedDate = DateTime(
      originalNextDate.year,
      originalNextDate.month + 1,
      originalNextDate.day,
    );
    final schedule = scheduledExpense(
      id: 'sched-projected',
      payee: 'Projected bill',
      amountMinor: 25000,
      nextDate: originalNextDate,
    );
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(scheduledTransactions: [schedule]),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);

    final row = find.byKey(
      ValueKey(
        'scheduled-row-sched-projected-${calendarDateId(projectedDate)}',
      ),
    );
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Scheduled Transaction'), findsOneWidget);
    expect(find.text(fullMonthDateLabel(projectedDate)), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.longPress(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Paid'));
    await tester.pumpAndSettle();
    expect(find.text(r'$250.00'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    final updated = dataStore.scheduledTransactions.single;
    expect(updated.nextDate, originalNextDate);
    expect(updated.occurrences, hasLength(1));
    expect(updated.occurrences.single.scheduledDate, projectedDate);
    expect(
      updated.occurrences.single.status,
      v2_scheduled.ScheduledOccurrenceStatus.paid,
    );
    final generated = dataStore.transactions.singleWhere(
      (transaction) => transaction.scheduledTransactionId == 'sched-projected',
    );
    expect(generated.scheduledOccurrenceDate, projectedDate);
    expect(generated.scheduledPlannedAmountMinor, 25000);
    expect(row, findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$250.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-paid')))
          .data,
      r'$250.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-remaining')))
          .data,
      r'$0.00',
    );
  });

  testWidgets('deleted paid occurrence is historical and not actionable', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final occurrenceDate = DateTime(now.year, now.month, 21);
    final occurrence = v2_scheduled.ScheduledOccurrenceRecord(
      scheduledDate: occurrenceDate,
      plannedAmountMinor: 2167,
      status: v2_scheduled.ScheduledOccurrenceStatus.paid,
      actualAmountMinor: 2167,
      actualPaymentDate: occurrenceDate,
      transactionId: 'txn-deleted-parent-paid',
    );
    final schedule =
        scheduledExpense(
          id: 'sched-deleted-parent',
          payee: 'Netflix',
          amountMinor: 2167,
          nextDate: occurrenceDate,
        ).copyWith(
          occurrences: [occurrence],
          sync: v2_sync.SyncMetadata.fresh().deleted(),
        );
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final transaction = v2_transaction.TransactionRecord(
      id: 'txn-deleted-parent-paid',
      type: v2_transaction.TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      date: occurrenceDate,
      payee: 'Netflix',
      amountMinor: 2167,
      scheduledTransactionId: schedule.id,
      scheduledOccurrenceDate: occurrenceDate,
      scheduledPlannedAmountMinor: 2167,
      sync: v2_sync.SyncMetadata.fresh(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        scheduledTransactions: [schedule],
        transactions: [...migrated.transactions, transaction],
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);

    final row = find.byKey(
      ValueKey(
        'scheduled-row-sched-deleted-parent-${calendarDateId(occurrenceDate)}',
      ),
    );
    expect(row, findsNothing);
    expect(
      dataStore.transactions
          .singleWhere((item) => item.id == transaction.id)
          .isDeleted,
      isFalse,
    );
    expect(dataStore.scheduledTransactions.single.occurrences, [occurrence]);
  });

  testWidgets('future scheduled edit and delete apply from selected occurrence', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final originalNextDate = DateTime(now.year, now.month - 1, 7);
    final currentProjection = DateTime(now.year, now.month, 7);
    final futureProjection = DateTime(now.year, now.month + 1, 7);
    final historicalOccurrence = v2_scheduled.ScheduledOccurrenceRecord(
      scheduledDate: DateTime(now.year, now.month - 2, 7),
      plannedAmountMinor: 25000,
      status: v2_scheduled.ScheduledOccurrenceStatus.paid,
      actualAmountMinor: 25000,
      actualPaymentDate: DateTime(now.year, now.month - 2, 7),
    );
    final editSchedule = scheduledExpense(
      id: 'sched-future-edit',
      payee: 'Future edit',
      amountMinor: 25000,
      nextDate: originalNextDate,
    ).copyWith(occurrences: [historicalOccurrence]);
    final deleteSchedule = scheduledExpense(
      id: 'sched-future-delete',
      payee: 'Future delete',
      amountMinor: 4000,
      nextDate: originalNextDate,
    ).copyWith(occurrences: [historicalOccurrence]);
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        scheduledTransactions: [editSchedule, deleteSchedule],
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);

    final editRow = find.byKey(
      ValueKey(
        'scheduled-row-sched-future-edit-${calendarDateId(currentProjection)}',
      ),
    );
    await tester.longPress(editRow);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text(fullMonthDateLabel(currentProjection)), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-amount')),
      '30000',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('scheduled-single-category-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scheduled-split-category-field')),
      findsNothing,
    );
    final projectedSave = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(projectedSave).onPressed, isNotNull);
    await tester.tap(projectedSave);
    await tester.pumpAndSettle();

    final originalAfterEdit = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-future-edit',
    );
    final edited = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id != 'sched-future-edit' && item.payee == 'Future edit',
    );
    expect(
      originalAfterEdit.endDate,
      currentProjection.subtract(const Duration(days: 1)),
    );
    expect(originalAfterEdit.amountMinor, 25000);
    final retainedHistory = originalAfterEdit.occurrences.singleWhere(
      (item) =>
          item.scheduledDate.year == historicalOccurrence.scheduledDate.year &&
          item.scheduledDate.month ==
              historicalOccurrence.scheduledDate.month &&
          item.scheduledDate.day == historicalOccurrence.scheduledDate.day,
    );
    expect(retainedHistory.status, historicalOccurrence.status);
    expect(
      retainedHistory.actualAmountMinor,
      historicalOccurrence.actualAmountMinor,
    );
    expect(
      retainedHistory.actualPaymentDate,
      historicalOccurrence.actualPaymentDate,
    );
    expect(edited.nextDate, currentProjection);
    expect(edited.amountMinor, 30000);
    expect(edited.occurrences, isEmpty);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    final deleteRow = find.byKey(
      ValueKey(
        'scheduled-row-sched-future-delete-${calendarDateId(futureProjection)}',
      ),
    );
    await tester.longPress(deleteRow);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Scheduled Transaction?'), findsOneWidget);
    await tester.tap(find.text('Delete Schedule'));
    await tester.pumpAndSettle();

    final ended = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-future-delete',
    );
    expect(ended.isDeleted, isFalse);
    expect(ended.endDate, futureProjection.subtract(const Duration(days: 1)));
    expect(
      ended.occurrences.any(
        (item) =>
            item.scheduledDate.year ==
                historicalOccurrence.scheduledDate.year &&
            item.scheduledDate.month ==
                historicalOccurrence.scheduledDate.month &&
            item.scheduledDate.day == historicalOccurrence.scheduledDate.day &&
            item.status == historicalOccurrence.status,
      ),
      isTrue,
    );
    expect(deleteRow, findsNothing);
  });

  testWidgets(
    'scheduled active alert card targets exact occurrence and clears on skip',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final now = DateTime.now();
      final dueDate = DateTime(now.year, now.month, now.day);
      final schedule = rentSchedule(nextDate: dueDate).copyWith(
        alertPreference: v2_scheduled.AlertPreference.sameDay,
        customAlertTimeMinutes: 0,
      );
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          preferences: migrated.preferences.copyWith(
            notificationsEnabled: true,
          ),
          scheduledTransactions: [schedule],
        ),
      );

      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      expect(find.byType(CountBadge), findsOneWidget);
      await tester.tap(find.text('Scheduled').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('scheduled-needs-attention-card')),
        findsOneWidget,
      );
      expect(find.text('Needs Attention'), findsOneWidget);
      expect(
        find.text(
          'Payment due ${shortMonthName(dueDate.month)} ${dueDate.day}',
        ),
        findsOneWidget,
      );
      final alertKey = ValueKey(
        'scheduled-alert-${schedule.id}:${dueDate.year}-${dueDate.month}-${dueDate.day}',
      );
      await tester.tap(find.byKey(alertKey));
      await tester.pump(const Duration(milliseconds: 400));
      final highlightKey = ValueKey(
        'scheduled-occurrence-highlight-${schedule.id}-${calendarDateId(dueDate)}',
      );
      final highlighted = tester.widget<AnimatedContainer>(
        find.byKey(highlightKey),
      );
      expect(
        (highlighted.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
      );
      final highlightRect = tester.getRect(find.byKey(highlightKey));
      final dayCardRect = tester.getRect(
        find.byKey(ValueKey('scheduled-day-card-${calendarDateId(dueDate)}')),
      );
      expect(highlightRect.left, closeTo(dayCardRect.left + 1, 0.1));
      expect(highlightRect.right, closeTo(dayCardRect.right - 1, 0.1));
      final occurrenceMarker = tester.widget<AnimatedContainer>(
        find.byKey(
          ValueKey(
            'scheduled-occurrence-marker-${schedule.id}-${calendarDateId(dueDate)}',
          ),
        ),
      );
      expect(occurrenceMarker.constraints?.maxWidth, 3);

      final occurrenceRow = find.byKey(
        ValueKey('scheduled-row-${schedule.id}-${calendarDateId(dueDate)}'),
      );
      await tester.ensureVisible(occurrenceRow);
      await tester.pumpAndSettle();
      await tester.longPress(occurrenceRow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip Once'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('scheduled-needs-attention-card')),
        findsNothing,
      );
      expect(dataStore.scheduledActiveAlertCount(), 0);
    },
  );

  testWidgets(
    'notification target opens Scheduled and highlights exact occurrence',
    (tester) async {
      final legacyStore = FinanceStore.seeded();
      final now = DateTime.now();
      final dueDate = DateTime(now.year, now.month, now.day + 2);
      final schedule = rentSchedule(
        nextDate: dueDate,
      ).copyWith(alertPreference: v2_scheduled.AlertPreference.oneWeekBefore);
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          preferences: migrated.preferences.copyWith(
            notificationsEnabled: true,
          ),
          scheduledTransactions: [schedule],
        ),
      );
      scheduledNotificationLaunchPayload.value = ScheduledNotificationPayload(
        scheduledTransactionId: schedule.id,
        occurrenceDate: dueDate,
      ).encode();

      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.pump(const Duration(milliseconds: 450));

      expect(find.text('Scheduled occurrences'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            'scheduled-occurrence-highlight-${schedule.id}-${calendarDateId(dueDate)}',
          ),
        ),
        findsOneWidget,
      );
      scheduledNotificationLaunchPayload.value = null;
    },
  );

  testWidgets('mark as paid records actual amount and occurrence once', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final dueDate = DateTime(now.year, now.month, now.day);
    final paymentDate = dueDate.subtract(const Duration(days: 2));
    final schedule = rentSchedule(nextDate: dueDate).copyWith(
      amountMinor: 25000,
      note: 'Recurring note',
      alertPreference: v2_scheduled.AlertPreference.sameDay,
    );
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final scheduler = TestNotificationScheduler();
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        preferences: migrated.preferences.copyWith(notificationsEnabled: true),
        scheduledTransactions: [schedule],
      ),
      notificationScheduler: scheduler,
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    final scheduledRentRow = find.byKey(
      ValueKey('scheduled-row-${schedule.id}-${calendarDateId(dueDate)}'),
    );
    await tester.ensureVisible(scheduledRentRow);
    await tester.longPress(scheduledRentRow);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Paid'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Paid'), findsOneWidget);
    expect(find.text(r'$250.00'), findsWidgets);
    expect(find.text('Today'), findsWidgets);
    final amountField = tester.widget<TextField>(
      find.byKey(const ValueKey('mark-paid-actual-amount')),
    );
    expect(amountField.controller!.text, r'$250.00');
    expect(find.text('Split Categories'), findsNothing);
    expect(
      find.byKey(const ValueKey('mark-paid-single-category-field')),
      findsOneWidget,
    );
    expect(find.text('Dining'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('mark-paid-actual-amount')),
      '0',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('mark-paid-actual-amount')),
      '90000',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNotNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('mark-paid-note')),
      'Occurrence note',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('mark-paid-date')));
    await tester.tap(find.byKey(const ValueKey('mark-paid-date')));
    await tester.pumpAndSettle();
    tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .onDateChanged(paymentDate);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final confirm = find.widgetWithText(FilledButton, 'Confirm');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    final paidTransactions = dataStore.transactions
        .where(
          (transaction) => transaction.scheduledTransactionId == 'sched-rent',
        )
        .toList();
    expect(paidTransactions, hasLength(1));
    final paid = paidTransactions.single;
    expect(paid.type, v2_transaction.TransactionType.expense);
    expect(paid.amountMinor, 90000);
    expect(isSameCalendarDay(paid.date, paymentDate), isTrue);
    expect(paid.date, isNot(paymentDate));
    expect(
      ledgerTransactionTimeLabel(
        tester.element(find.byType(Scaffold).first),
        paid.date,
      ),
      isNotNull,
    );
    expect(paid.payee, 'Rent');
    expect(paid.categoryId, 'dining');
    expect(paid.splitLines, isEmpty);
    expect(paid.isCategorySplit, isFalse);
    expect(paid.note, 'Occurrence note');
    expect(paid.scheduledOccurrenceDate, dueDate);
    expect(paid.scheduledPlannedAmountMinor, 25000);

    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(scheduled.amountMinor, 25000);
    expect(
      scheduled.nextDate,
      DateTime(dueDate.year, dueDate.month + 1, dueDate.day),
    );
    expect(scheduled.note, 'Recurring note');
    expect(scheduled.lastAction, v2_scheduled.ScheduledAction.none);
    expect(scheduled.occurrences, hasLength(1));
    expect(
      scheduled.occurrences.single.status,
      v2_scheduled.ScheduledOccurrenceStatus.paid,
    );
    expect(scheduled.occurrences.single.plannedAmountMinor, 25000);
    expect(scheduled.occurrences.single.actualAmountMinor, 90000);
    expect(scheduled.occurrences.single.actualPaymentDate, paid.date);
    expect(scheduler.scheduledIds, contains('sched-rent'));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$250.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-paid')))
          .data,
      r'$900.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-remaining')))
          .data,
      r'$0.00',
    );
  });

  testWidgets('mark paid preserves planned splits when actual amount matches', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final dueDate = DateTime(now.year, now.month, now.day);
    final schedule = rentSchedule(nextDate: dueDate).copyWith(
      amountMinor: 10000,
      splitLines: const [
        v2_transaction.TransactionSplitLine(
          id: 'planned-dining',
          categoryId: 'dining',
          amountMinor: 6000,
        ),
        v2_transaction.TransactionSplitLine(
          id: 'planned-snacks',
          categoryId: 'snacks',
          amountMinor: 4000,
        ),
      ],
    );
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(scheduledTransactions: [schedule]),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Paid'));
    await tester.pumpAndSettle();

    expect(find.text('Split Categories'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mark-paid-single-category-field')),
      findsNothing,
    );
    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('Snacks'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Confirm');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    final paid = dataStore.transactions.singleWhere(
      (transaction) => transaction.scheduledTransactionId == schedule.id,
    );
    expect(paid.amountMinor, 10000);
    expect(paid.splitLines, hasLength(2));
    expect(paid.splitLines.map((line) => line.amountMinor), [6000, 4000]);
    final future = dataStore.scheduledTransactions.single;
    expect(future.amountMinor, 10000);
    expect(future.splitLines.map((line) => line.amountMinor), [6000, 4000]);
  });

  testWidgets('scheduled long press can mark transfer paid', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final dueDate = DateTime(now.year, now.month, now.day);
    final scheduledTransfer = rentSchedule(nextDate: dueDate).copyWith(
      type: v2_transaction.TransactionType.transfer,
      transferAccountId: 'cash',
      payee: 'Cash draw',
      amountMinor: 5000,
      clearCategory: true,
    );
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(scheduledTransactions: [scheduledTransfer]);
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.tap(find.text('Cash draw'));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('From Account'), findsOneWidget);
    expect(find.text('To Account'), findsOneWidget);
    expect(find.text('Category'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.ensureVisible(find.text('Cash draw'));
    await tester.longPress(find.text('Cash draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Paid'));
    await tester.pumpAndSettle();

    expect(find.text('From Account'), findsOneWidget);
    expect(find.text('To Account'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('mark-paid-actual-amount')),
          )
          .controller!
          .text,
      r'$50.00',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    final paid = dataStore.transactions.singleWhere(
      (transaction) => transaction.scheduledTransactionId == 'sched-rent',
    );
    expect(paid.type, v2_transaction.TransactionType.transfer);
    expect(paid.accountId, 'checking');
    expect(paid.transferAccountId, 'cash');
    expect(paid.categoryId, isNull);
    expect(paid.amountMinor, 5000);
    expect(paid.payee, 'Cash draw');
    expect(paid.scheduledOccurrenceDate, dueDate);

    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(scheduled.accountId, isNot(scheduled.transferAccountId));
    expect(scheduled.lastAction, v2_scheduled.ScheduledAction.none);
    expect(
      scheduled.occurrences.single.status,
      v2_scheduled.ScheduledOccurrenceStatus.paid,
    );
  });

  testWidgets('mark as paid preserves scheduled income payee and category', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final schedule =
        rentSchedule(nextDate: DateTime(now.year, now.month, now.day)).copyWith(
          type: v2_transaction.TransactionType.income,
          categoryId: 'income',
          payee: 'Salary',
          amountMinor: 125000,
        );
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(scheduledTransactions: [schedule]);
    final dataStore = FinanceDataStore(dataSet: dataSet);
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.ensureVisible(find.text('Salary'));
    await tester.longPress(find.text('Salary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Paid'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    final paid = dataStore.transactions.singleWhere(
      (transaction) => transaction.scheduledTransactionId == 'sched-rent',
    );
    expect(paid.type, v2_transaction.TransactionType.income);
    expect(paid.payee, 'Salary');
    expect(paid.categoryId, 'income');
    expect(paid.amountMinor, 125000);
  });

  testWidgets('skip once records skipped occurrence without transaction', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final dueDate = DateTime(now.year, now.month, now.day);
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(scheduledTransactions: [rentSchedule(nextDate: dueDate)]);
    final dataStore = FinanceDataStore(dataSet: dataSet);
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.ensureVisible(find.text('Rent'));
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip Once'));
    await tester.pumpAndSettle();

    expect(
      dataStore.transactions.where(
        (transaction) => transaction.scheduledTransactionId == 'sched-rent',
      ),
      isEmpty,
    );
    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(scheduled.occurrences, hasLength(1));
    expect(
      scheduled.occurrences.single.status,
      v2_scheduled.ScheduledOccurrenceStatus.skipped,
    );
  });

  testWidgets('scheduled long press can duplicate and delete item', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          scheduledTransactions: [
            rentSchedule(
              nextDate: DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day,
              ),
            ),
          ],
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.ensureVisible(find.text('Rent'));
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(
      dataStore.scheduledTransactions.map((item) => item.payee),
      contains('Rent copy'),
    );
    expect(find.text('Rent copy'), findsOneWidget);

    await collapseScheduledCalendar(tester);
    await tester.ensureVisible(find.text('Rent'));
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Scheduled Transaction?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      dataStore.scheduledTransactions
          .singleWhere((item) => item.id == 'sched-rent')
          .isDeleted,
      isFalse,
    );

    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Schedule'));
    await tester.pumpAndSettle();

    final original = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(original.isDeleted, isTrue);
    expect(find.text('Rent'), findsNothing);
    expect(find.text('Rent copy'), findsOneWidget);
  });

  testWidgets('scheduled long press can edit item', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          scheduledTransactions: [
            rentSchedule(nextDate: DateTime(now.year, now.month, now.day)),
          ],
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.ensureVisible(find.text('Rent'));
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Scheduled Transaction'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-payee')),
      'Mortgage',
    );
    await tester.enterText(
      find.byKey(const ValueKey('scheduled-amount')),
      '925.50',
    );
    expect(
      find.byKey(const ValueKey('scheduled-single-category-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scheduled-split-category-field')),
      findsNothing,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('scheduled-next-date')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scheduled-next-date')));
    await tester.pumpAndSettle();
    tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .onDateChanged(DateTime(2026, 8, 15));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final edited = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(edited.payee, 'Mortgage');
    expect(edited.amountMinor, 92550);
    expect(edited.nextDate, DateTime(2026, 8, 15));
    expect(edited.frequency, v2_scheduled.RecurrenceFrequency.monthly);
    expect(edited.lastAction, v2_scheduled.ScheduledAction.none);
    await tester.ensureVisible(find.byTooltip('Next month'));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('Mortgage'), findsOneWidget);
    expect(find.text('Rent'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('scheduled-month-planned')))
          .data,
      r'$925.50',
    );
  });

  testWidgets('scheduled edit persists custom alert options', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final now = DateTime.now();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          scheduledTransactions: [
            rentSchedule(
              nextDate: DateTime(now.year, now.month, now.day),
            ).copyWith(
              alertPreference: v2_scheduled.AlertPreference.custom,
              customAlertTimeMinutes: 11 * 60 + 15,
              repeatAlertUntilResolved: true,
            ),
          ],
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await collapseScheduledCalendar(tester);
    await tester.ensureVisible(find.text('Rent'));
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Time'), findsOneWidget);
    expect(find.text('11:15 AM'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('scheduled-repeat-alert')),
    );
    await tester.tap(find.byKey(const ValueKey('scheduled-repeat-alert')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final edited = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(edited.alertPreference, v2_scheduled.AlertPreference.custom);
    expect(edited.customAlertTimeMinutes, 11 * 60 + 15);
    expect(edited.repeatAlertUntilResolved, isFalse);
  });

  testWidgets('budgets screen renders v2 budget progress text', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();

    expect(find.text('Dining'), findsOneWidget);
    expect(find.textContaining('spent of'), findsWidgets);
    expect(find.textContaining('Monthly ·'), findsWidgets);
    expect(find.textContaining('Categories:'), findsWidgets);
  });

  testWidgets('budget dialog creates budget with categories', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add budget'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Fuel');
    await tester.enterText(fields.at(1), '250.00');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Dining'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-rollover')), findsOneWidget);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final budget = dataStore.budgets.singleWhere((item) => item.name == 'Fuel');
    expect(budget.amountMinor, 25000);
    expect(budget.categoryIds, contains('dining'));
    expect(budget.period, BudgetPeriod.monthly);
    expect(budget.rolloverEnabled, isFalse);
    expect(budget.configurationRevisions, hasLength(1));
    expect(find.text('Fuel'), findsOneWidget);
  });

  testWidgets('budget long press can rename budget', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Food');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(
      dataStore.budgets.singleWhere((item) => item.id == 'b1').name,
      'Food',
    );
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('budget long press archives budget', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(
      dataStore.budgets.singleWhere((item) => item.name == 'Dining').isArchived,
      isTrue,
    );
    expect(find.text('Dining'), findsNothing);
  });

  testWidgets('budget long press can delete budget', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete budget?'), findsOneWidget);
    await tester.tap(find.text('Delete Budget'));
    await tester.pumpAndSettle();

    final budget = dataStore.budgets.singleWhere(
      (item) => item.name == 'Dining',
    );
    expect(budget.isArchived, isTrue);
    expect(budget.isDeleted, isTrue);
    expect(find.text('Dining'), findsNothing);
  });

  testWidgets('Plan switches between Budgets and Goals and remembers segment', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    expect(find.text('Plan'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Budgets'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('plan-segmented-control')),
      findsOneWidget,
    );
    expect(find.text('Dining'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('plan-segmented-control')),
        matching: find.text('Goals'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No Goals yet'), findsOneWidget);
    expect(dataStore.preferences.preferredPlanSegment, PlanSegment.goals);

    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    final control = tester.widget<SegmentedButton<PlanSegment>>(
      find.byKey(const ValueKey('plan-segmented-control')),
    );
    expect(control.selected, {PlanSegment.goals});
  });

  testWidgets('Plan Goals floating add menu exposes Goal actions', (
    tester,
  ) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('plan-segmented-control')),
        matching: find.text('Goals'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Create Goal'), findsWidgets);
    expect(find.text('Fund Goals'), findsWidgets);
    expect(find.text('Add Budget'), findsNothing);
  });

  testWidgets('categories screen renders v2 categories on wide layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();

    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('Expense'), findsWidgets);
  });

  testWidgets('management count pills share width and cap overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ManagementCountPill(
                key: ValueKey('four-digit-pill'),
                count: 9999,
              ),
              ManagementCountPill(key: ValueKey('overflow-pill'), count: 10000),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('four-digit-pill'))),
      const Size(58, 28),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('overflow-pill'))),
      const Size(58, 28),
    );
    expect(find.text('9999'), findsOneWidget);
    expect(find.text('9999+'), findsOneWidget);
  });

  testWidgets('categories screen indents subcategories', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataSet = migrated.copyWith(
      categories: [
        for (final category in migrated.categories)
          if (category.id == 'snacks')
            category.copyWith(parentCategoryId: 'dining')
          else
            category,
      ],
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();

    expect(find.text('Snacks'), findsNothing);
    expect(find.text('Expense · 1 subcategory'), findsOneWidget);
    expect(find.byTooltip('Expand Dining'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand Dining'));
    await tester.pumpAndSettle();
    expect(find.text('Expense · Dining'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Snacks')).dx,
      greaterThan(tester.getTopLeft(find.text('Dining')).dx),
    );
    expect(
      find.byKey(const ValueKey('category-branch-snacks')),
      findsOneWidget,
    );
    final parentBadge = tester.widget<CategoryIconBadge>(
      find.descendant(
        of: find.byKey(const ValueKey('category-row-dining')),
        matching: find.byType(CategoryIconBadge),
      ),
    );
    final childBadge = tester.widget<CategoryIconBadge>(
      find.descendant(
        of: find.byKey(const ValueKey('category-row-snacks')),
        matching: find.byType(CategoryIconBadge),
      ),
    );
    expect(parentBadge.size, CategoryIconBadgeSize.row);
    expect(childBadge.size, CategoryIconBadgeSize.compact);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('category-count-dining')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('category-row-snacks')),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Collapse Dining'));
    await tester.pumpAndSettle();
    expect(find.text('Snacks'), findsNothing);
    expect(find.text('Expense · 1 subcategory'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand Dining'));
    await tester.pumpAndSettle();
    expect(find.text('Snacks'), findsOneWidget);
    expect(find.text('Expense · Dining'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('category-swipe-snacks')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-archive-snacks')));
    await tester.pumpAndSettle();
    expect(dataStore.categoryById('snacks').isArchived, isTrue);
    expect(find.text('Snacks'), findsNothing);
  });

  testWidgets('category dialog creates a v2-only category', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fuel');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Fuel'), findsOneWidget);
    expect(
      dataStore.categories.map((category) => category.name),
      contains('Fuel'),
    );
  });

  testWidgets('category dialog opens with unknown legacy icon and color', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        categories: [
          for (final category in migrated.categories)
            if (category.id == 'dining')
              category.copyWith(
                iconName: 'old-unknown-icon',
                colorValue: 0xFFABCDEF,
              )
            else
              category,
        ],
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-row-dining')));
    await tester.pumpAndSettle();

    expect(find.text('Category Details'), findsOneWidget);
    expect(find.text('Edit Category'), findsNothing);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Category'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category long press archives category', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(dataStore.categoryById('dining').isArchived, isTrue);
    expect(find.text('Dining'), findsNothing);
  });

  testWidgets('category long press can delete category', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    final category = dataStore.categoryById('dining');
    expect(category.isArchived, isTrue);
    expect(category.isDeleted, isTrue);
    expect(find.text('Dining'), findsNothing);
  });

  testWidgets('category count pill opens the exact rolling Ledger filter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-count-dining')));
    await tester.pumpAndSettle();

    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('Category: Dining'), findsOneWidget);
    expect(find.text('Period: Last 12 Months'), findsOneWidget);
    expect(find.text('Diner'), findsOneWidget);
    expect(find.text('Walmart'), findsNothing);
    expect(find.text('Clear Filter'), findsOneWidget);

    await tester.tap(find.text('Clear Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Walmart'), findsOneWidget);
  });

  testWidgets('payee manager groups archived payees and restores them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        preferences: migrated.preferences.copyWith(
          savedPayeeNames: const ['Walmart', 'Cafe', 'Old Store'],
          archivedPayeeNames: const {'cafe', 'old store'},
          deletedPayeeNames: const {'old store'},
        ),
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final managePayees = find.widgetWithText(ListTile, 'Manage payees');
    await tester.ensureVisible(managePayees);
    await tester.pumpAndSettle();
    await tester.tap(managePayees);
    await tester.pumpAndSettle();

    expect(find.text('Payees'), findsOneWidget);
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('archived-payee-cafe')), findsNothing);
    expect(find.text('Old Store'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('archived-payees-header')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('archived-payee-cafe')), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(dataStore.preferences.archivedPayeeNames, isNot(contains('cafe')));
    expect(find.text('Archived (1)'), findsNothing);
    expect(find.text('Cafe'), findsOneWidget);
    expect(
      savedPayees(
        dataStore,
      ).map((payee) => payee.toLowerCase()).where((payee) => payee == 'cafe'),
      hasLength(1),
    );
  });

  testWidgets('payee manager alphabetizes sections counts and swipe actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        preferences: migrated.preferences.copyWith(
          savedPayeeNames: const ['Burger King', 'Apple', 'Best Buy', 'Amazon'],
        ),
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final managePayees = find.widgetWithText(ListTile, 'Manage payees');
    await tester.ensureVisible(managePayees);
    await tester.pumpAndSettle();
    await tester.tap(managePayees);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('payee-section-A')), findsOneWidget);
    expect(find.byKey(const ValueKey('payee-section-B')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Amazon')).dy,
      lessThan(tester.getTopLeft(find.text('Apple')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Best Buy')).dy,
      lessThan(tester.getTopLeft(find.text('Burger King')).dy),
    );
    expect(find.byIcon(Icons.person_outline), findsNothing);
    expect(find.byType(Divider), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('payee-count-apple')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    final payeePillSize = tester.getSize(
      find.byKey(const ValueKey('payee-count-apple')),
    );
    expect(payeePillSize, const Size(58, 28));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('payee-row-apple')),
        matching: find.byIcon(AppIcon.chevronRight),
      ),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('payee-row-apple'))).height,
      44,
    );

    final bestBuySwipe = find.byKey(const ValueKey('payee-swipe-best buy'));
    await tester.ensureVisible(bestBuySwipe);
    await tester.drag(bestBuySwipe, const Offset(-240, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payee-archive-best buy')));
    await tester.pumpAndSettle();

    expect(dataStore.preferences.archivedPayeeNames, contains('best buy'));
    expect(find.byKey(const ValueKey('payee-row-best buy')), findsNothing);
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('archived-payee-best buy')), findsNothing);
  });

  testWidgets('payee count includes transfer to its destination account', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final source = migrated.accounts.first;
    final creditOne = v2_account.AccountRecord(
      id: 'credit-one-payee-count',
      name: 'Credit One',
      type: v2_account.AccountType.creditCard,
      openingBalanceMinor: 0,
      sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
    );
    final payment = v2_transaction.TransactionRecord(
      id: 'credit-one-payment',
      type: v2_transaction.TransactionType.transfer,
      accountId: source.id,
      transferAccountId: creditOne.id,
      date: DateTime.now(),
      payee: 'Credit One',
      amountMinor: 10000,
      sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        accounts: [...migrated.accounts, creditOne],
        transactions: [...migrated.transactions, payment],
        preferences: migrated.preferences.copyWith(
          savedPayeeNames: const ['Credit One'],
        ),
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Manage payees'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('payee-count-credit one')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('payee-count-credit one')));
    await tester.pumpAndSettle();
    expect(find.text('Payee: Credit One'), findsOneWidget);
    expect(find.text('Period: Last 12 Months'), findsOneWidget);
  });

  testWidgets('payee tap shows details, long press actions, and pill Ledger', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Manage payees'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('payee-row-diner')));
    await tester.pumpAndSettle();
    expect(find.text('Payee Details'), findsOneWidget);
    expect(find.text('Edit payee'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('payee-row-diner')));
    await tester.pumpAndSettle();
    expect(find.text('Delete permanently'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('payee-count-diner')));
    await tester.pumpAndSettle();
    expect(find.text('Payee: Diner'), findsOneWidget);
    expect(find.text('Period: Last 12 Months'), findsOneWidget);
    expect(find.text('Diner'), findsWidgets);
    expect(find.text('Walmart'), findsNothing);
  });

  testWidgets('system balance-adjustment label is not a manageable payee', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        transactions: [
          ...migrated.transactions,
          v2_transaction.TransactionRecord(
            id: 'system-adjustment',
            type: v2_transaction.TransactionType.adjustment,
            accountId: migrated.accounts.first.id,
            date: DateTime.now(),
            payee: 'Balance adjustment',
            amountMinor: 5000,
            sync: v2_sync.SyncMetadata.fresh(),
          ),
        ],
        preferences: migrated.preferences.copyWith(
          savedPayeeNames: [
            ...migrated.preferences.savedPayeeNames,
            'Balance adjustment',
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Manage payees'));
    await tester.pumpAndSettle();

    expect(find.text('Balance adjustment'), findsNothing);
  });

  testWidgets('permanently deleted payee stays deleted after reload and sync', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        preferences: migrated.preferences.copyWith(
          savedPayeeNames: const ['Cafe'],
          archivedPayeeNames: const {'cafe'},
        ),
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final managePayees = find.widgetWithText(ListTile, 'Manage payees');
    await tester.ensureVisible(managePayees);
    await tester.pumpAndSettle();
    await tester.tap(managePayees);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('archived-payees-header')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete Cafe permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently').last);
    await tester.pumpAndSettle();

    expect(dataStore.preferences.deletedPayeeNames, contains('cafe'));
    expect(dataStore.preferences.archivedPayeeNames, isNot(contains('cafe')));
    expect(savedPayees(dataStore), isNot(contains('Cafe')));
    expect(archivedPayees(dataStore), isNot(contains('Cafe')));

    final reloadedStore = FinanceDataStore(
      dataSet: FinanceDataSet.fromJson(dataStore.dataSet.toJson()),
    );
    expect(reloadedStore.preferences.deletedPayeeNames, contains('cafe'));
    expect(savedPayees(reloadedStore), isNot(contains('Cafe')));

    final staleRemote = migrated.copyWith(
      preferences: migrated.preferences.copyWith(
        savedPayeeNames: const ['Cafe'],
      ),
    );
    final merged = mergeFinanceDataSetsPreferCurrent(
      incoming: staleRemote,
      current: reloadedStore.dataSet,
    );
    final mergedStore = FinanceDataStore(dataSet: merged);
    expect(mergedStore.preferences.deletedPayeeNames, contains('cafe'));
    expect(savedPayees(mergedStore), isNot(contains('Cafe')));
    expect(
      savedPayees(mergedStore)
          .map((payee) => payee.toLowerCase())
          .toSet()
          .intersection(
            archivedPayees(
              mergedStore,
            ).map((payee) => payee.toLowerCase()).toSet(),
          ),
      isEmpty,
    );
  });

  testWidgets('archived and deleted payees stay out of suggestions', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        preferences: migrated.preferences.copyWith(
          savedPayeeNames: const ['Walmart', 'Cafe'],
          archivedPayeeNames: const {'cafe'},
          deletedPayeeNames: const {'walmart'},
        ),
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    final payeeField = find.byKey(const ValueKey('transaction-payee'));
    await tester.enterText(payeeField, 'Wal');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('payee-suggestion-Walmart')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('payee-suggestion-__create_new_payee__')),
      findsOneWidget,
    );
  });

  testWidgets('settings screen renders v2 preferences on wide layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('App Preferences'), findsOneWidget);
    expect(find.text('Launch screen'), findsOneWidget);
    expect(find.text('Money Format'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Manage accounts'), findsOneWidget);
    expect(find.text('Manage categories'), findsOneWidget);
    expect(find.text('Manage budgets'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Reports'), findsOneWidget);
    final dataManagementRow = find.byKey(const ValueKey('data-management-row'));
    expect(dataManagementRow, findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Export CSV'), findsNothing);

    await tester.ensureVisible(dataManagementRow);
    await tester.pumpAndSettle();
    await tester.tap(dataManagementRow);
    await tester.pumpAndSettle();

    expect(find.text('Data Management'), findsWidgets);
    expect(find.widgetWithText(ListTile, 'Export CSV'), findsOneWidget);
    expect(find.byKey(const ValueKey('data-management-row')), findsNothing);
  });

  testWidgets('settings preference rows update and persist stored values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    const repository = LocalFinanceDataSetRepository(
      storageKey: 'polished_settings_preferences_test',
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        preferences: migrated.preferences.copyWith(notificationsEnabled: true),
      ),
      localRepository: repository,
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Launch screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Floating add button'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Default transaction type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();

    for (final label in const [
      'Show Icons',
      'Show Timestamps',
      'Show Split Indicator',
      'Show Running Balance',
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(TrackmarkSwitchListTile),
        ),
      );
      await tester.pumpAndSettle();
    }

    expect(dataStore.preferences.launchScreen, LaunchScreen.ledger);
    expect(dataStore.preferences.appearanceMode, AppearanceMode.dark);
    expect(
      dataStore.preferences.floatingAddButtonPosition,
      FloatingAddButtonPosition.left,
    );
    expect(
      dataStore.preferences.defaultTransactionType,
      DefaultTransactionType.income,
    );
    expect(dataStore.preferences.notificationsEnabled, isTrue);
    expect(dataStore.preferences.showLedgerIcons, isFalse);
    expect(dataStore.preferences.showLedgerTimestamps, isFalse);
    expect(dataStore.preferences.showLedgerSplitIndicator, isFalse);
    expect(dataStore.preferences.showRunningBalance, isTrue);
    expect(find.text('Your data is stored securely'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final reloaded = await FinanceDataStore.load(localRepository: repository);
    expect(reloaded.preferences.launchScreen, LaunchScreen.ledger);
    expect(reloaded.preferences.appearanceMode, AppearanceMode.dark);
    expect(
      reloaded.preferences.floatingAddButtonPosition,
      FloatingAddButtonPosition.left,
    );
    expect(
      reloaded.preferences.defaultTransactionType,
      DefaultTransactionType.income,
    );
    expect(reloaded.preferences.notificationsEnabled, isTrue);
    expect(reloaded.preferences.showLedgerIcons, isFalse);
    expect(reloaded.preferences.showLedgerTimestamps, isFalse);
    expect(reloaded.preferences.showLedgerSplitIndicator, isFalse);
    expect(reloaded.preferences.showRunningBalance, isTrue);
  });

  testWidgets('settings money format rows update and persist', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    const repository = LocalFinanceDataSetRepository(
      storageKey: 'polished_settings_money_test',
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated,
      localRepository: repository,
    );
    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('USD — US Dollar'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Currency'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EUR — Euro').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Decimal places'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Thousands separator'));
    await tester.tap(find.widgetWithText(ListTile, 'Thousands separator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Period').last);
    await tester.pumpAndSettle();

    expect(dataStore.preferences.currency.currencyCode, 'EUR');
    expect(dataStore.preferences.currency.decimalPlaces, 0);
    expect(dataStore.preferences.currency.thousandsSeparator, '.');
    final reloaded = await FinanceDataStore.load(localRepository: repository);
    expect(reloaded.preferences.currency.currencyCode, 'EUR');
    expect(reloaded.preferences.currency.decimalPlaces, 0);
    expect(reloaded.preferences.currency.thousandsSeparator, '.');
  });

  testWidgets('settings cloud sync rows preserve callbacks and status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    var syncCount = 0;
    var signOutCount = 0;
    await tester.pumpWidget(
      FinanceStoreScope(
        store: legacyStore,
        child: FinanceDataStoreScope(
          store: dataStore,
          child: MaterialApp(
            home: FinanceHome(
              syncLabel: 'Synced',
              lastSuccessfulSyncLabel: 'Today at 8:39 AM',
              syncDiagnosticLabel: 'Incremental · ~13 reads · 1 write · manual',
              onSyncNow: () async => syncCount += 1,
              onSignOut: () => signOutCount += 1,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('Your data is securely synced'), findsOneWidget);
    expect(find.text('Today at 8:39 AM'), findsOneWidget);
    expect(find.text('Last sync activity'), findsOneWidget);
    expect(
      find.text('Incremental · ~13 reads · 1 write · manual'),
      findsOneWidget,
    );
    expect(find.text('Automatic Sync'), findsOneWidget);
    expect(find.text('Preferred Daily Sync Time'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Sync now'));
    await tester.pumpAndSettle();
    expect(syncCount, 1);
    final automaticSync = find.widgetWithText(
      TrackmarkSwitchListTile,
      'Automatic Sync',
    );
    await tester.ensureVisible(automaticSync);
    await tester.tap(automaticSync);
    await tester.pumpAndSettle();
    expect(dataStore.preferences.automaticSyncEnabled, isTrue);
    final signOut = find.widgetWithText(ListTile, 'Sign out');
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(signOutCount, 1);
  });

  testWidgets('settings keeps sync diagnostics discoverable before capture', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    await tester.pumpWidget(
      FinanceStoreScope(
        store: legacyStore,
        child: FinanceDataStoreScope(
          store: dataStore,
          child: MaterialApp(
            home: FinanceHome(syncLabel: 'Synced', onSyncNow: () async {}),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('Last sync activity'), findsOneWidget);
    expect(find.text('Run Sync now to collect details'), findsOneWidget);
  });

  testWidgets('settings disables repeated sync taps and shows real progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    var syncCount = 0;
    await tester.pumpWidget(
      FinanceStoreScope(
        store: legacyStore,
        child: FinanceDataStoreScope(
          store: dataStore,
          child: MaterialApp(
            home: FinanceHome(
              syncLabel: 'Syncing',
              onSyncNow: () async => syncCount += 1,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings').last);
    await tester.pump();

    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.text('Refreshing your Trackmark data'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Syncing…'));
    await tester.pump();
    expect(syncCount, 0);
  });

  testWidgets('mobile settings more card opens reports', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final reports = find.widgetWithText(ListTile, 'Reports');
    await tester.ensureVisible(reports);
    await tester.pumpAndSettle();
    await tester.tap(reports);
    await tester.pumpAndSettle();

    expect(find.text('Spending by Category'), findsOneWidget);
    expect(find.text('Monthly Trend'), findsOneWidget);
    expect(find.byTooltip('Add'), findsNothing);
  });

  testWidgets(
    'settings management rows navigate to accounts categories budgets',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MoneyTallyApp());

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      final manageAccounts = find.widgetWithText(ListTile, 'Manage accounts');
      await tester.ensureVisible(manageAccounts);
      await tester.pumpAndSettle();
      await tester.tap(manageAccounts);
      await tester.pumpAndSettle();

      expect(find.text('Manage Accounts'), findsOneWidget);
      expect(find.text('Defaults'), findsOneWidget);
      expect(find.text('New Account Defaults'), findsOneWidget);
      expect(find.text('Display & Totals'), findsOneWidget);
      expect(find.text('Warnings'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      final manageCategories = find.widgetWithText(
        ListTile,
        'Manage categories',
      );
      await tester.ensureVisible(manageCategories);
      await tester.pumpAndSettle();
      await tester.tap(manageCategories);
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsWidgets);
      expect(find.text('Dining'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      final manageBudgets = find.widgetWithText(ListTile, 'Manage budgets');
      await tester.ensureVisible(manageBudgets);
      await tester.pumpAndSettle();
      await tester.tap(manageBudgets);
      await tester.pumpAndSettle();

      expect(find.text('Budgets'), findsWidgets);
      expect(find.text('Dining'), findsOneWidget);
    },
  );

  testWidgets('settings toggles notification preference', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final notifications = find.widgetWithText(
      TrackmarkSwitchListTile,
      'Scheduled transaction alerts',
    );
    await tester.ensureVisible(notifications);
    await tester.pumpAndSettle();
    await tester.tap(notifications);
    await tester.pumpAndSettle();

    expect(dataStore.preferences.notificationsEnabled, isTrue);
  });

  testWidgets('settings can save custom currency code and symbol', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom currency'));
    await tester.tap(find.widgetWithText(ListTile, 'Custom currency'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Currency code'),
      'mxn',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Symbol'), r'MX$ ');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(dataStore.preferences.currency.currencyCode, 'MXN');
    expect(dataStore.preferences.currency.symbol, r'MX$ ');
    expect(find.text(r'MXN MX$ '), findsOneWidget);
  });

  testWidgets('settings export action sheets preserve clipboard exports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final clipboardWrites = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final data = call.arguments as Map<Object?, Object?>;
          clipboardWrites.add(data['text']! as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final dataManagementRow = find.byKey(const ValueKey('data-management-row'));
    await tester.ensureVisible(dataManagementRow);
    await tester.pumpAndSettle();
    await tester.tap(dataManagementRow);
    await tester.pumpAndSettle();
    final exportCsv = find.widgetWithText(ListTile, 'Export CSV');
    await tester.ensureVisible(exportCsv);
    await tester.pumpAndSettle();
    await tester.tap(exportCsv);
    await tester.pumpAndSettle();
    expect(find.text('Share CSV File'), findsOneWidget);
    expect(find.text('Copy CSV to Clipboard'), findsOneWidget);
    await tester.tap(find.text('Copy CSV to Clipboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('CSV copied to clipboard'), findsOneWidget);
    expect(clipboardWrites.single, contains('transaction_id,split_line_id'));
    await tester.pump(const Duration(seconds: 4));

    final exportBackup = find.widgetWithText(ListTile, 'Export Backup');
    await tester.ensureVisible(exportBackup);
    await tester.pumpAndSettle();
    await tester.tap(exportBackup);
    await tester.pumpAndSettle();
    expect(find.text('Share Backup File'), findsOneWidget);
    expect(find.text('Copy JSON to Clipboard'), findsOneWidget);
    await tester.tap(find.text('Copy JSON to Clipboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(clipboardWrites.length, 2);
    expect(clipboardWrites.last, contains('"accounts"'));
    expect(find.text('Backup copied to clipboard'), findsOneWidget);
  });

  testWidgets('settings shares real export files with an anchored origin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final exportFileService = RecordingExportFileService(holdFirstShare: true);
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceDataStoreScope(
          store: dataStore,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SettingsView(
                dataManagementOnly: true,
                exportFileService: exportFileService,
                now: () => DateTime(2026, 7, 23, 22, 45),
              ),
            ),
          ),
        ),
      ),
    );

    final exportCsv = find.widgetWithText(ListTile, 'Export CSV');
    await tester.ensureVisible(exportCsv);
    await tester.tap(exportCsv);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share CSV File'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(exportFileService.recordedShares, hasLength(1));
    final csvShare = exportFileService.recordedShares.single;
    expect(csvShare.fileName, 'money_tally_transactions_2026-07-23.csv');
    expect(csvShare.mimeType, 'text/csv');
    expect(csvShare.sharePositionOrigin.width, greaterThan(0));
    expect(csvShare.sharePositionOrigin.height, greaterThan(0));
    expect(csvShare.content, contains('transaction_id,split_line_id'));

    await tester.tap(exportCsv);
    await tester.pump();
    expect(find.text('Share CSV File'), findsNothing);
    expect(exportFileService.recordedShares, hasLength(1));

    exportFileService.firstShare.complete(
      const ExportedFile(
        path: '/temporary/money_tally_transactions_2026-07-23.csv',
        fileName: 'money_tally_transactions_2026-07-23.csv',
        mimeType: 'text/csv',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Could not share CSV file'), findsNothing);

    final exportBackup = find.widgetWithText(ListTile, 'Export Backup');
    await tester.ensureVisible(exportBackup);
    await tester.tap(exportBackup);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share Backup File'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(exportFileService.recordedShares, hasLength(2));
    final backupShare = exportFileService.recordedShares.last;
    expect(
      backupShare.fileName,
      'trackmark_money_backup_2026-07-23_224500.json',
    );
    expect(backupShare.mimeType, 'application/json');
    expect(backupShare.content, contains('"accounts"'));
    expect(
      const BackupCodec().decodeJson(backupShare.content).accounts.length,
      dataStore.dataSet.accounts.length,
    );
  });

  testWidgets(
    'settings reset requires typed confirmation and creates a safety backup',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final legacyStore = FinanceStore.seeded();
      final original = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final resetSource = original.copyWith(
        preferences: original.preferences.copyWith(
          savedPayeeNames: const ['Walmart', 'Cafe'],
          archivedPayeeNames: const {'cafe'},
          deletedPayeeNames: const {'old store'},
        ),
      );
      final dataStore = FinanceDataStore(dataSet: resetSource);
      final safetyService = RecordingBackupSafetyFileService();

      await tester.pumpWidget(
        MaterialApp(
          home: FinanceDataStoreScope(
            store: dataStore,
            child: Scaffold(
              body: SingleChildScrollView(
                child: SettingsView(
                  dataManagementOnly: true,
                  syncLabel: 'Local only',
                  backupSafetyFileService: safetyService,
                  now: () => DateTime(2026, 8, 23, 10, 11, 12),
                ),
              ),
            ),
          ),
        ),
      );

      final resetRow = find.byKey(const ValueKey('reset-trackmark-data-row'));
      await tester.ensureVisible(resetRow);
      await tester.tap(resetRow);
      await tester.pumpAndSettle();

      expect(find.text('Reset Trackmark Data?'), findsOneWidget);
      final confirmationField = tester.widget<TextField>(
        find.byKey(const ValueKey('reset-trackmark-data-confirmation')),
      );
      expect(confirmationField.decoration?.labelText, isNull);
      expect(confirmationField.decoration?.hintText, 'RESET');
      expect(
        confirmationField.decoration?.hintStyle?.fontWeight,
        FontWeight.w400,
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('reset-trackmark-data-confirmation'),
                ),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
      final resetButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm-trackmark-data-reset')),
      );
      expect(resetButton.onPressed, isNull);
      expect(dataStore.accounts, isNotEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('reset-trackmark-data-confirmation')),
        'RESET',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('confirm-trackmark-data-reset')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trackmark Data Reset'), findsOneWidget);
      expect(dataStore.accounts, isEmpty);
      expect(dataStore.categories, isEmpty);
      expect(dataStore.transactions, isEmpty);
      expect(dataStore.scheduledTransactions, isEmpty);
      expect(dataStore.budgets, isEmpty);
      expect(dataStore.goals, isEmpty);
      expect(dataStore.funds, isEmpty);
      expect(dataStore.reservationOperations, isEmpty);
      expect(dataStore.preferences.savedPayeeNames, isEmpty);
      expect(dataStore.preferences.archivedPayeeNames, isEmpty);
      expect(dataStore.preferences.deletedPayeeNames, isEmpty);
      expect(
        dataStore.preferences.currency.toJson(),
        original.preferences.currency.toJson(),
      );
      expect(safetyService.savedAt, DateTime(2026, 8, 23, 10, 11, 12));
      final restoredSafety = const BackupRestoreValidator().validate(
        safetyService.savedContent!,
      );
      expect(restoredSafety.dataSet.accounts.length, original.accounts.length);
      expect(restoredSafety.dataSet.preferences.savedPayeeNames, [
        'Walmart',
        'Cafe',
      ]);
    },
  );

  testWidgets('settings reset can also restore app preferences to defaults', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final original = const V1SnapshotMigrator().migrate(
      FinanceStore.seeded().snapshot().toJson(),
    );
    final customized = original.copyWith(
      preferences: const UserPreferences(
        launchScreen: LaunchScreen.ledger,
        preferredPlanSegment: PlanSegment.goals,
        appearanceMode: AppearanceMode.dark,
        floatingAddButtonPosition: FloatingAddButtonPosition.left,
        automaticSyncEnabled: true,
        automaticBackupsEnabled: true,
        automaticBackupLocation: AutomaticBackupLocation.iCloud,
        showLedgerIcons: false,
        savedPayeeNames: ['Walmart'],
        archivedPayeeNames: {'old store'},
        deletedPayeeNames: {'deleted store'},
        legacyV1MigrationCompleted: true,
      ),
    );
    final dataStore = FinanceDataStore(dataSet: customized);
    final safetyService = RecordingBackupSafetyFileService();

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceDataStoreScope(
          store: dataStore,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SettingsView(
                dataManagementOnly: true,
                syncLabel: 'Local only',
                backupSafetyFileService: safetyService,
                now: () => DateTime(2026, 8, 24, 9, 30),
              ),
            ),
          ),
        ),
      ),
    );

    final resetRow = find.byKey(const ValueKey('reset-trackmark-data-row'));
    await tester.ensureVisible(resetRow);
    await tester.tap(resetRow);
    await tester.pumpAndSettle();
    final resetSettingsCheckbox = find.descendant(
      of: find.byKey(const ValueKey('reset-app-settings-too')),
      matching: find.byType(Checkbox),
    );
    await tester.tap(resetSettingsCheckbox);
    await tester.pump();
    expect(tester.widget<Checkbox>(resetSettingsCheckbox).value, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('reset-trackmark-data-confirmation')),
      'RESET',
    );
    await tester.pump();
    expect(tester.widget<Checkbox>(resetSettingsCheckbox).value, isTrue);
    await tester.tap(
      find.byKey(const ValueKey('confirm-trackmark-data-reset')),
    );
    await tester.pumpAndSettle();

    const expected = UserPreferences(legacyV1MigrationCompleted: true);
    expect(dataStore.preferences.toJson(), expected.toJson());
    final restoredSafety = const BackupRestoreValidator().validate(
      safetyService.savedContent!,
    );
    expect(
      restoredSafety.dataSet.preferences.toJson(),
      customized.preferences.toJson(),
    );
  });

  testWidgets('settings reports temporary export creation failures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      ),
    );
    final exportFileService = RecordingExportFileService(
      failure: StateError('Temporary directory unavailable'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceDataStoreScope(
          store: dataStore,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SettingsView(
                dataManagementOnly: true,
                exportFileService: exportFileService,
              ),
            ),
          ),
        ),
      ),
    );

    final exportBackup = find.widgetWithText(ListTile, 'Export Backup');
    await tester.ensureVisible(exportBackup);
    await tester.tap(exportBackup);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share Backup File'));
    await tester.pumpAndSettle();

    expect(find.text('Could not share backup file'), findsOneWidget);
  });

  testWidgets('launch screen preference selects initial finance section', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.reports,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    expect(find.text('Reports'), findsWidgets);
    expect(find.text('Spending by Category'), findsOneWidget);
    expect(find.text('Monthly Trend'), findsOneWidget);
  });

  testWidgets('launch preference opens the intended Plan segment', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.planGoals,
            preferredPlanSegment: PlanSegment.goals,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Plan'), findsWidgets);
    expect(find.text('No Goals yet'), findsOneWidget);
    final control = tester.widget<SegmentedButton<PlanSegment>>(
      find.byKey(const ValueKey('plan-segmented-control')),
    );
    expect(control.selected, {PlanSegment.goals});
  });

  testWidgets('reports screen is reachable from wide navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();

    expect(find.text('Spending by Category'), findsOneWidget);
    expect(find.text('Monthly Trend'), findsOneWidget);
    expect(find.text('Income'), findsWidgets);
    expect(find.text('Expenses'), findsWidgets);
    expect(find.text('Net Cash Flow'), findsOneWidget);
    // Seeded data remains historical as time moves forward; navigation is the
    // behavior under test rather than a hard-coded current-month total.
    expect(find.text('Walmart'), findsWidgets);
    expect(find.byTooltip('Add'), findsNothing);
  });

  testWidgets('applies v2 appearance preference to app theme mode', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            appearanceMode: AppearanceMode.dark,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme, isNotNull);
  });
}

Future<void> selectScheduledCalendarFilter(
  WidgetTester tester,
  String filter,
) async {
  await tester.tap(
    find.byKey(const ValueKey('calendar-activity-filter-picker')),
  );
  await tester.pumpAndSettle();
  final option = find.byKey(ValueKey('calendar-filter-$filter'));
  if (option.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      option,
      120,
      scrollable: find.byType(Scrollable).last,
    );
  } else {
    await tester.ensureVisible(option);
  }
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

String _monthYearLabel(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

class FakeRemoteFinanceRepository implements FinanceRemoteRepository {
  final Map<String, FinanceSnapshot> snapshots = {};

  @override
  Future<FinanceSnapshot?> loadSnapshot({required String userId}) async {
    return snapshots[userId];
  }

  @override
  Future<void> saveSnapshot({
    required String userId,
    required FinanceSnapshot snapshot,
  }) async {
    snapshots[userId] = FinanceSnapshot.fromJson(snapshot.toJson());
  }
}

v2_scheduled.ScheduledTransactionRecord rentSchedule({DateTime? nextDate}) {
  return scheduledExpense(
    id: 'sched-rent',
    payee: 'Rent',
    amountMinor: 90000,
    nextDate: nextDate ?? DateTime(2026, 8),
  );
}

v2_scheduled.ScheduledTransactionRecord scheduledExpense({
  required String id,
  required String payee,
  required int amountMinor,
  required DateTime nextDate,
}) {
  return v2_scheduled.ScheduledTransactionRecord(
    id: id,
    type: v2_transaction.TransactionType.expense,
    accountId: 'checking',
    categoryId: 'dining',
    payee: payee,
    amountMinor: amountMinor,
    nextDate: nextDate,
    frequency: v2_scheduled.RecurrenceFrequency.monthly,
    sync: v2_sync.SyncMetadata.fresh(),
  );
}
