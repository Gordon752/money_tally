import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/funds/recurring_fund_cycle_calculator.dart';
import 'package:money_tally/src/ledger/running_balance_calculator.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_restore_service.dart';

// Entirely synthetic, in-memory fixtures: no Firebase, device storage or network.
void main() {
  final today = DateTime(2026, 9, 7);
  final sync = SyncMetadata.fresh(now: today, deviceId: 'stress-fixture');
  final accounts = [
    for (final id in ['checking', 'savings'])
      AccountRecord(
        id: id,
        name: id,
        type: AccountType.checking,
        openingBalanceMinor: 100000000,
        sync: sync,
      ),
  ];
  FinanceDataSet data(List<TransactionRecord> transactions) => FinanceDataSet(
    accounts: accounts,
    categories: const [],
    transactions: transactions,
    scheduledTransactions: const [],
    budgets: const [],
    preferences: const UserPreferences(),
  );

  test(
    '20,000 mixed records preserve balance buckets and validated backup',
    () {
      final random = Random(752);
      final cleared = [100000000, 100000000];
      final pending = [0, 0];
      var pendingOutflows = 0;
      final transactions = <TransactionRecord>[];
      for (var i = 0; i < 20000; i++) {
        final amount = 1 + random.nextInt(100000);
        final type = [
          TransactionType.expense,
          TransactionType.income,
          TransactionType.transfer,
        ][i % 3];
        final isPending = i % 5 == 0;
        final future = i % 17 == 0;
        transactions.add(
          TransactionRecord(
            id: 't-$i',
            type: type,
            accountId: 'checking',
            transferAccountId: type == TransactionType.transfer
                ? 'savings'
                : null,
            date: future
                ? today.add(const Duration(days: 10))
                : today.subtract(Duration(days: i % 3650)),
            payee: 'Synthetic $i',
            amountMinor: amount,
            sync: sync,
            status: isPending
                ? TransactionStatus.pending
                : TransactionStatus.cleared,
          ),
        );
        if (!future) {
          if (isPending && type != TransactionType.income) {
            pendingOutflows += amount;
          }
          final bucket = isPending ? pending : cleared;
          bucket[0] += type == TransactionType.income ? amount : -amount;
          if (type == TransactionType.transfer) bucket[1] += amount;
        }
      }
      final source = data(transactions);
      final timer = Stopwatch()..start();
      for (var i = 0; i < accounts.length; i++) {
        final id = accounts[i].id;
        expect(source.clearedBalanceForAccount(id, asOf: today), cleared[i]);
        expect(source.pendingEffectForAccount(id, asOf: today), pending[i]);
        expect(
          source.availableToSpendForAccount(id, asOf: today),
          cleared[i] - (i == 0 ? pendingOutflows : 0),
        );
        final eligible = transactions.where(
          (t) =>
              t.status == TransactionStatus.cleared && !t.date.isAfter(today),
        );
        final running = calculateAccountRunningBalances(
          account: accounts[i],
          transactions: eligible,
        );
        expect(running.afterTransaction.values.last, cleared[i]);
      }
      final encoded = const BackupCodec().encodeJson(source, exportedAt: today);
      final restored = const BackupRestoreValidator().validate(encoded).dataSet;
      expect(restored.toJson(), source.toJson());
      expect(
        () => const BackupRestoreValidator().validate(
          encoded.substring(0, encoded.length ~/ 2),
        ),
        throwsA(isA<BackupValidationException>()),
      );
      // Diagnostic only: debug test-runner timing is not release UI performance.
      // ignore: avoid_print
      print(
        'STRESS 20k balance/running-ledger/backup: ${timer.elapsedMilliseconds} ms; ${encoded.length} JSON characters',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '1,000 spend/return sequences retain independently computed coverage',
    () {
      final fund = FundRecord(
        id: 'bills',
        name: 'Bills',
        fundingAccountId: 'checking',
        status: FundStatus.active,
        sync: sync,
        targetBalanceMinor: 360000,
        targetCadence: FundTargetCadence.monthly,
        targetDayRule: FundTargetDayRule.endOfMonth,
        nextTargetDate: DateTime(2026, 9, 30),
      );
      final operations = <ReservationOperationRecord>[];
      final transactions = <TransactionRecord>[];
      void operation(
        ReservationOperationKind kind,
        int amount, {
        String? transactionId,
      }) {
        final n = operations.length;
        operations.add(
          ReservationOperationRecord(
            id: 'op-$n',
            containerType: ReservationContainerType.fund,
            containerId: fund.id,
            fundingAccountId: 'checking',
            kind: kind,
            amountMinor: amount,
            effectiveDate: today,
            revision: n + 1,
            baseRevision: n,
            operationId: 'op-$n',
            deviceId: 'stress-fixture',
            sync: sync,
            transactionId: transactionId,
          ),
        );
      }

      operation(ReservationOperationKind.allocate, 1080000);
      var reserved = 1080000;
      var consumed = 0;
      for (var i = 0; i < 1000; i++) {
        final id = 'spend-$i';
        transactions.add(
          TransactionRecord(
            id: id,
            type: TransactionType.expense,
            accountId: 'checking',
            date: today,
            payee: 'Synthetic bill',
            amountMinor: 100,
            sync: sync,
            reservationContainerType: ReservationContainerType.fund,
            reservationContainerId: fund.id,
          ),
        );
        operation(ReservationOperationKind.consume, 100, transactionId: id);
        operation(ReservationOperationKind.returnFunds, 50);
        reserved -= 150;
        consumed += 100;
        if (i % 50 == 49) {
          final snapshot = calculateRecurringFundCycleProgress(
            fund: fund,
            effectiveOperations: operations,
            transactions: transactions,
            asOf: today,
          );
          expect(snapshot.reservedMinor, reserved);
          expect(snapshot.completedCycles, (reserved + consumed) ~/ 360000);
          expect(
            snapshot.activeCycleFundedMinor,
            (reserved + consumed) % 360000,
          );
        }
      }
      final shuffled = [...operations]..shuffle(Random(42));
      final snapshot = calculateRecurringFundCycleProgress(
        fund: fund,
        effectiveOperations: shuffled,
        transactions: transactions.reversed,
        asOf: today,
      );
      expect(snapshot.reservedMinor, reserved);
      expect(snapshot.activeCycleFundedMinor, (reserved + consumed) % 360000);
      final source = data(
        transactions,
      ).copyWith(funds: [fund], reservationOperations: operations);
      expect(source.reservedForAccount('checking', asOf: today), reserved);
      expect(
        source.availableToSpendForAccount('checking', asOf: today),
        100000000 - consumed - reserved,
      );
      expect(
        const BackupRestoreValidator()
            .validate(const BackupCodec().encodeJson(source, exportedAt: today))
            .dataSet
            .toJson(),
        source.toJson(),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
