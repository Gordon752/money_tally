import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as app;
import 'package:money_tally/src/design/design_tokens.dart';
import 'package:money_tally/src/design/widgets/account_card.dart';
import 'package:money_tally/src/design/widgets/amount_entry_field.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/ledger/transaction_account_preview.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

final _now = DateTime(2026, 9, 5, 12);
final _sync = SyncMetadata.fresh(now: _now);

FinanceDataSet _dataSet({List<TransactionRecord> transactions = const []}) =>
    FinanceDataSet(
      accounts: [
        AccountRecord(
          id: 'card',
          name: 'Chase',
          type: AccountType.creditCard,
          openingBalanceMinor: -262317,
          creditLimitMinor: 290000,
          sync: _sync,
        ),
        AccountRecord(
          id: 'cash',
          name: 'Checking',
          type: AccountType.checking,
          openingBalanceMinor: 500000,
          sync: _sync,
        ),
        AccountRecord(
          id: 'loan',
          name: 'Loan',
          type: AccountType.loan,
          openingBalanceMinor: -1000000,
          sync: _sync,
        ),
      ],
      categories: [
        CategoryRecord(
          id: 'expense',
          name: 'Dining',
          kind: CategoryKind.expense,
          sync: _sync,
        ),
        CategoryRecord(
          id: 'income',
          name: 'Salary',
          kind: CategoryKind.income,
          sync: _sync,
        ),
      ],
      transactions: transactions,
      scheduledTransactions: const [],
      budgets: const [],
      preferences: const UserPreferences(),
    );

TransactionAccountPreview _preview(
  FinanceDataSet data, {
  TransactionType type = TransactionType.expense,
  String accountId = 'card',
  String? to,
  TransactionStatus status = TransactionStatus.cleared,
  DateTime? date,
  TransactionRecord? replacing,
}) => TransactionAccountPreview(
  dataSet: data,
  type: type,
  accountId: accountId,
  transferAccountId: to,
  amountMinor: 200000,
  date: date ?? _now,
  status: status,
  replacing: replacing,
  asOf: _now,
);

void main() {
  for (final scheduled in [false, true]) {
    testWidgets(
      '${scheduled ? 'scheduled' : 'transfer'} focuses amount without an account and after choosing one',
      (tester) async {
        final store = FinanceDataStore(dataSet: _dataSet());
        await _open(tester, store, (context) async {
          if (scheduled) {
            await app.showScheduledTransactionDialog(context);
          } else {
            await app.showTransferDialog(context);
          }
        }, width: 393);
        final field = find.byKey(
          ValueKey(scheduled ? 'scheduled-amount' : 'transfer-amount'),
        );
        TextField amount() => tester.widget<TextField>(field);
        expect(amount().focusNode!.hasFocus, isTrue);
        await tester.enterText(field, '12345');
        for (final name in ['Checking', 'Chase']) {
          final row = find.byKey(
            ValueKey(scheduled ? 'scheduled-account' : 'transfer-from-account'),
          );
          await tester.ensureVisible(row);
          await tester.tap(row);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, name));
          await tester.pumpAndSettle();
          expect(amount().focusNode!.hasFocus, isTrue);
          expect(amount().controller!.text, r'$123.45');
        }
        expect(store.transactions, isEmpty);
        expect(store.scheduledTransactions, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        store.dispose();
      },
      variant: TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }),
    );
  }
  for (final mode in [
    AccountDefaultMode.none,
    AccountDefaultMode.specific,
    AccountDefaultMode.lastUsed,
  ]) {
    testWidgets(
      'new transaction focuses amount with $mode and after account selection',
      (tester) async {
        final store = FinanceDataStore(
          dataSet: _dataSet().copyWith(
            preferences: UserPreferences(
              defaultTransactionAccountMode: mode,
              defaultTransactionAccountId: 'card',
              lastUsedTransactionAccountId: 'card',
            ),
          ),
        );
        await _open(
          tester,
          store,
          app.showDefaultTransactionDialog,
          width: 393,
        );
        final field = find.byKey(const ValueKey('transaction-amount'));
        TextField amount() => tester.widget<TextField>(field);
        expect(amount().focusNode!.hasFocus, isTrue);
        final accountRow = find.byKey(
          const ValueKey('transaction-account-row'),
        );
        expect(
          find.descendant(
            of: accountRow,
            matching: find.text('Choose account'),
          ),
          mode == AccountDefaultMode.none ? findsOneWidget : findsNothing,
        );
        // Entering money must survive selecting or changing the account.
        await tester.enterText(field, '12345');
        await tester.pump();
        for (final name in ['Checking', 'Chase']) {
          await tester.ensureVisible(accountRow);
          await tester.tap(accountRow);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, name));
          await tester.pumpAndSettle();
          expect(amount().focusNode!.hasFocus, isTrue);
          expect(amount().controller!.text, r'$123.45');
          expect(amount().controller!.selection.isCollapsed, isTrue);
        }
        expect(store.transactions, isEmpty);
        expect(store.preferences.defaultTransactionAccountMode, mode);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        store.dispose();
      },
      variant: TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }),
    );
  }

  test(
    'preview reuses signed expense/income/transfer deltas for assets and liabilities',
    () {
      final data = _dataSet();
      final original = data.toJson();
      for (final account in data.accounts) {
        expect(
          _preview(data, accountId: account.id).balanceMinor(account.id),
          account.openingBalanceMinor - 200000,
        );
        expect(
          _preview(
            data,
            accountId: account.id,
            type: TransactionType.income,
          ).balanceMinor(account.id),
          account.openingBalanceMinor + 200000,
        );
      }
      final transfer = _preview(
        data,
        type: TransactionType.transfer,
        accountId: 'cash',
        to: 'card',
      );
      expect(transfer.balanceMinor('cash'), 300000);
      expect(transfer.balanceMinor('card'), -62317);
      expect(transfer.availableCreditMinor(data.accounts.first), 227683);
      final cashAdvance = _preview(
        data,
        type: TransactionType.transfer,
        accountId: 'card',
        to: 'cash',
      );
      expect(cashAdvance.balanceMinor('card'), -462317);
      expect(cashAdvance.balanceMinor('cash'), 700000);
      expect(
        data.toJson(),
        original,
        reason: 'Typing never mutates authoritative records.',
      );
    },
  );

  test('preview keeps pending and future separate from cleared Balance', () {
    final data = _dataSet();
    final pending = _preview(data, status: TransactionStatus.pending);
    expect(pending.balanceMinor('card'), -262317);
    expect(pending.pendingMinor('card'), -200000);
    expect(pending.availableCreditMinor(data.accounts.first), -172317);
    for (final status in TransactionStatus.values) {
      final future = _preview(data, status: status, date: DateTime(2026, 9, 6));
      expect(future.balanceMinor('card'), -262317);
      expect(future.pendingMinor('card'), 0);
      expect(future.futureMinor('card'), -200000);
      expect(future.availableCreditMinor(data.accounts.first), 27683);
    }
    final cleared = _preview(data);
    expect(cleared.balanceMinor('card'), -462317);
    expect(cleared.pendingMinor('card'), 0);
    expect(
      cleared.availableCreditMinor(data.accounts.first),
      pending.availableCreditMinor(data.accounts.first),
    );
  });

  test(
    'editing replaces existing record once including date/status/account changes',
    () {
      for (final status in TransactionStatus.values) {
        for (final date in [_now, DateTime(2026, 9, 10)]) {
          final original = TransactionRecord(
            id: 'edit',
            type: TransactionType.expense,
            accountId: 'card',
            amountMinor: 12300,
            date: date,
            status: status,
            payee: 'Original',
            sync: _sync,
          );
          final data = _dataSet(transactions: [original]);
          final edited = _preview(data, replacing: original);
          expect(edited.balanceMinor('card'), -462317);
          expect(edited.pendingMinor('card'), 0);
          expect(edited.futureMinor('card'), 0);
          final moved = _preview(data, accountId: 'cash', replacing: original);
          expect(moved.balanceMinor('card'), -262317);
          expect(moved.balanceMinor('cash'), 300000);
          expect(data.transactions.single, same(original));
        }
      }
    },
  );

  testWidgets(
    'typing a credit charge previews balance and available with a nonblocking live limit warning',
    (tester) async {
      final store = FinanceDataStore(dataSet: _dataSet());
      await _open(
        tester,
        store,
        (context) => app.showTransactionDialog(
          context,
          initialAccountId: 'card',
          initialIsExpense: true,
        ),
        width: 393,
      );
      final unchanged = store.dataSet.toJson();
      final amount = find.byKey(const ValueKey('transaction-amount'));
      final warning = find.byKey(const ValueKey('credit-limit-warning-card'));
      for (final input in ['10000', '27683']) {
        await tester.enterText(amount, input);
        await tester.pump();
        expect(warning, findsNothing);
      }
      expect(find.text(r'Balance $2,900.00'), findsOneWidget);
      expect(find.text(r'Available $0.00'), findsOneWidget);
      await tester.enterText(amount, '200000');
      await tester.pump();
      expect(find.text(r'Balance $4,623.17'), findsOneWidget);
      expect(find.text(r'Available -$1,723.17'), findsOneWidget);
      expect(
        find.text(r'Exceeds available credit by $1,723.17'),
        findsOneWidget,
      );
      expect(store.dataSet.toJson(), unchanged);
      await tester.enterText(amount, '10000');
      await tester.pump();
      expect(warning, findsNothing);
      expect(find.text(r'Balance $2,723.17'), findsOneWidget);
      await tester.enterText(amount, '200000');
      await tester.pump();
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining').last);
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('transaction-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.transactions, hasLength(1));
      expect(store.clearedBalanceForAccount('card'), -462317);
      expect(find.textContaining('overdraw'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'income preview reduces card debt; pending charge does not increase cleared Balance',
    (tester) async {
      final store = FinanceDataStore(dataSet: _dataSet());
      await _open(
        tester,
        store,
        (context) => app.showTransactionDialog(
          context,
          initialAccountId: 'card',
          initialIsExpense: false,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '200000',
      );
      await tester.pump();
      expect(find.text(r'Balance $623.17'), findsOneWidget);
      expect(find.text(r'Available $2,276.83'), findsOneWidget);
      await tester.tap(find.text('Expense').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('transaction-pending-toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text(r'Balance $2,623.17'), findsOneWidget);
      expect(find.text(r'Pending -$2,000.00'), findsOneWidget);
      expect(find.text(r'Available -$1,723.17'), findsOneWidget);
      expect(store.transactions, isEmpty);
    },
  );

  testWidgets('transfer preview updates source and destination while typing', (
    tester,
  ) async {
    final store = FinanceDataStore(dataSet: _dataSet());
    final transfer = TransactionRecord(
      id: 'transfer',
      type: TransactionType.transfer,
      accountId: 'cash',
      transferAccountId: 'card',
      amountMinor: 10000,
      date: DateTime.now(),
      payee: 'Payment',
      sync: _sync,
    );
    await _open(
      tester,
      store,
      (context) => app.showTransferDialog(context, transfer: transfer),
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-amount')),
      '200000',
    );
    await tester.pump();
    expect(find.text(r'Balance $3,000.00'), findsOneWidget);
    expect(find.text(r'Balance $623.17'), findsOneWidget);
    expect(find.text(r'Available $2,276.83'), findsOneWidget);
    expect(store.transactions, isEmpty);
  });

  for (final width in [320.0, 1024.0, 1440.0]) {
    for (final (used, percent) in [
      (87000, 30),
      (194300, 67),
      (290000, 100),
      (462317, 159),
    ]) {
      testWidgets(
        'credit utilization $percent% retains actual percentage and clamped bar at width $width',
        (tester) async {
          _size(tester, width);
          final account = _dataSet().accounts.first;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AccountCard(account: account, balanceMinor: -used),
              ),
            ),
          );
          expect(find.text('$percent% utilized'), findsOneWidget);
          expect(
            find.text('Over limit'),
            used > 290000 ? findsOneWidget : findsNothing,
          );
          final bar = tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
          expect(bar.value, (used / 290000).clamp(0.0, 1.0));
          expect(
            bar.color,
            creditUtilizationFillColor(
              used / 290000,
              brightness: Brightness.light,
            ),
          );
          if (used > 290000) {
            expect(
              find.text(r'Credit Available -$1,723.17 of $2,900.00'),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Mark as Paid amount focuses at end and previews a live over-limit charge',
    (tester) async {
      final item = ScheduledTransactionRecord(
        id: 'scheduled',
        type: TransactionType.expense,
        accountId: 'card',
        categoryId: 'expense',
        payee: 'Bill',
        amountMinor: 90694,
        nextDate: DateTime.now(),
        frequency: RecurrenceFrequency.monthly,
        sync: _sync,
      );
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(scheduledTransactions: [item]),
      );
      await _open(
        tester,
        store,
        (context) => app.markScheduledTransactionPaid(context, item),
      );
      await _expectCaretAtEnd(tester, 'mark-paid-actual-amount');
      expect(find.text(r'Balance $3,530.11'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('mark-paid-actual-amount')),
        '200000',
      );
      await tester.pump();
      expect(find.text(r'Balance $4,623.17'), findsOneWidget);
      expect(
        find.text(r'Exceeds available credit by $1,723.17'),
        findsOneWidget,
      );
      expect(store.transactions, isEmpty);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS}),
  );

  testWidgets(
    'Adjust Balance retains end-caret behavior on initial and repeat focus',
    (tester) async {
      final store = FinanceDataStore(dataSet: _dataSet());
      await _open(
        tester,
        store,
        (context) => app.showAdjustBalanceDialog(context, store.accounts.first),
      );
      await _expectCaretAtEnd(tester, 'account-adjust-balance');
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS}),
  );

  testWidgets(
    'amount component preserves intentional initial select-all for split editing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmountEntryField(
              initialMinor: 90694,
              autofocus: true,
              selectAllOnFocus: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.controller!.selection,
        TextSelection(
          baseOffset: 0,
          extentOffset: field.controller!.text.length,
        ),
      );
      field.focusNode!.unfocus();
      await tester.pumpAndSettle();
      field.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(
        field.controller!.selection,
        TextSelection.collapsed(offset: field.controller!.text.length),
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS}),
  );
}

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _open(
  WidgetTester tester,
  FinanceDataStore store,
  Future<void> Function(BuildContext) action, {
  double width = 1024,
}) async {
  _size(tester, width);
  await tester.pumpWidget(
    FinanceDataStoreScope(
      store: store,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => action(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _expectCaretAtEnd(WidgetTester tester, String key) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  final amountWidget = tester.widget<AmountEntryField>(
    find.ancestor(of: field, matching: find.byType(AmountEntryField)),
  );
  expect(amountWidget.selectAllOnFocus, isFalse);
  for (var tap = 0; tap < 3; tap++) {
    if (tap < 2) {
      await tester.tap(field);
    } else {
      tester.widget<TextField>(field).focusNode!.requestFocus();
    }
    await tester.pumpAndSettle();
    final textField = tester.widget<TextField>(field);
    expect(textField.focusNode!.hasFocus, isTrue);
    expect(
      textField.controller!.selection,
      TextSelection.collapsed(offset: textField.controller!.text.length),
    );
    textField.focusNode!.unfocus();
    await tester.pumpAndSettle();
  }
}
