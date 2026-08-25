import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart'
    show completeScheduledTransactionPayment, recordScheduledOccurrence;
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_restore_service.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  final occurrenceDate = DateTime(2026, 8, 24);

  test('scheduled Fund funding plan is optional and JSON compatible', () {
    final schedule = _schedule(occurrenceDate);

    final restored = ScheduledTransactionRecord.fromJson(schedule.toJson());

    expect(restored.type, TransactionType.goalFunding);
    expect(
      restored.reservationFundingContainerType,
      ReservationContainerType.fund,
    );
    expect(restored.reservationFundingContainerId, 'bills');

    final legacyJson = Map<String, Object?>.from(schedule.toJson())
      ..remove('reservationFundingContainerType')
      ..remove('reservationFundingContainerId');
    final legacy = ScheduledTransactionRecord.fromJson(legacyJson);
    expect(legacy.reservationFundingContainerType, isNull);
    expect(legacy.reservationFundingContainerId, isNull);
  });

  test(
    'backup round trip preserves scheduled Fund funding authority',
    () async {
      final store = _store(occurrenceDate);
      final allocation = await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );

      final encoded = const BackupCodec().encodeJson(
        store.dataSet,
        exportedAt: DateTime.utc(2026, 8, 24, 12),
      );
      final restored = const BackupCodec().decodeJson(encoded);
      final schedule = restored.scheduledTransactions.single;
      final occurrence =
          schedule.occurrenceStates[occurrenceDayKey(occurrenceDate)];

      expect(schedule.isScheduledFundFunding, isTrue);
      expect(
        schedule.reservationFundingContainerType,
        ReservationContainerType.fund,
      );
      expect(schedule.reservationFundingContainerId, 'bills');
      expect(occurrence?.status, ScheduledOccurrenceStatus.paid);
      expect(occurrence?.reservationOperationId, allocation.id);
      expect(restored.reservationOperations, hasLength(1));
      expect(
        restored.reservationOperations.single.toJson(),
        allocation.toJson(),
      );
      expect(restored.transactions, isEmpty);

      final restoredStore = FinanceDataStore(
        deviceId: 'restored-device',
        dataSet: restored,
      );
      expect(restoredStore.balanceForAccount('checking'), 500000);
      expect(restoredStore.netWorthMinor, 500000);
      expect(restoredStore.currentFundAmountMinor('bills'), 20000);
      expect(restoredStore.availableToSpendForAccount('checking'), 480000);
    },
  );

  test('backup decoder accepts schedules without Fund funding fields', () {
    final legacyData = _store(occurrenceDate).dataSet.toJson();
    final schedules = legacyData['scheduledTransactions']! as List<Object?>;
    final legacySchedule =
        Map<String, Object?>.from(schedules.single! as Map<String, Object?>)
          ..remove('reservationFundingContainerType')
          ..remove('reservationFundingContainerId');
    final legacyOccurrence = ScheduledOccurrenceState(
      scheduledDate: occurrenceDate,
      plannedAmountMinor: 20000,
      status: ScheduledOccurrenceStatus.paid,
      revision: 1,
      operationId: 'legacy-paid',
      changedAt: DateTime.utc(2026, 8, 24),
      deviceId: 'legacy-device',
    ).toJson()..remove('reservationOperationId');
    legacySchedule['occurrenceStates'] = {
      occurrenceDayKey(occurrenceDate): legacyOccurrence,
    };
    legacyData['scheduledTransactions'] = [legacySchedule];

    final restored = const BackupCodec().decodeJson(jsonEncode(legacyData));

    expect(restored.scheduledTransactions, hasLength(1));
    expect(
      restored.scheduledTransactions.single.reservationFundingContainerType,
      isNull,
    );
    expect(
      restored.scheduledTransactions.single.reservationFundingContainerId,
      isNull,
    );
    expect(
      restored
          .scheduledTransactions
          .single
          .occurrenceStates[occurrenceDayKey(occurrenceDate)]
          ?.reservationOperationId,
      isNull,
    );
    expect(restored.accounts.single.id, 'checking');
    expect(restored.funds.single.id, 'bills');
  });

  test(
    'strict restore accepts valid scheduled Fund funding and legacy schedules',
    () async {
      final store = _store(occurrenceDate);
      await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );

      expect(
        const BackupRestoreValidator()
            .validate(const BackupCodec().encodeJson(store.dataSet))
            .dataSet
            .scheduledTransactions
            .single
            .isScheduledFundFunding,
        isTrue,
      );

      final legacySchedule = ScheduledTransactionRecord(
        id: 'legacy-rent',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'rent',
        payee: 'Landlord',
        amountMinor: 10000,
        nextDate: occurrenceDate,
        frequency: RecurrenceFrequency.monthly,
        sync: store.dataSet.scheduledTransactions.single.sync,
      );
      final legacyData = store.dataSet.copyWith(
        scheduledTransactions: [legacySchedule],
        reservationOperations: const [],
      );
      final rawLegacy = _backupMap(legacyData);
      _rawSchedules(rawLegacy).single
        ..remove('reservationFundingContainerType')
        ..remove('reservationFundingContainerId')
        ..remove('occurrenceStates');

      expect(
        const BackupRestoreValidator()
            .validate(jsonEncode(rawLegacy))
            .dataSet
            .scheduledTransactions
            .single
            .id,
        'legacy-rent',
      );
    },
  );

  test('strict restore rejects malformed active Fund funding plans', () {
    final source = _store(occurrenceDate).dataSet;
    final corruptions = <void Function(Map<String, Object?>)>[
      (raw) => _rawSchedules(raw).single['amountMinor'] = 0,
      (raw) => _rawFunds(raw).single['status'] = FundStatus.archived.name,
      (raw) => _rawAccounts(raw).single['type'] = AccountType.creditCard.name,
      (raw) => _rawSchedules(raw).single['categoryId'] = 'rent',
      (raw) => _rawSchedules(raw).single['transferAccountId'] = 'checking',
      (raw) => _rawSchedules(raw).single['splitLines'] = [
        {'id': 'split-rent', 'categoryId': 'rent', 'amountMinor': 20000},
      ],
      (raw) => _rawSchedules(raw).single['goalFundingAllocations'] = [
        {'goalId': 'missing-goal', 'amountMinor': 20000},
      ],
      (raw) {
        final schedule = _rawSchedules(raw).single;
        schedule['reservationContainerType'] =
            ReservationContainerType.fund.name;
        schedule['reservationContainerId'] = 'bills';
      },
    ];

    for (final corrupt in corruptions) {
      final raw = _backupMap(source);
      corrupt(raw);
      expect(
        () => const BackupRestoreValidator().validate(jsonEncode(raw)),
        throwsA(isA<BackupValidationException>()),
      );
    }
  });

  test('strict restore validates raw occurrence-state status values', () {
    final raw = _backupMap(_store(occurrenceDate).dataSet);
    _rawSchedules(raw).single['occurrenceStates'] = {
      occurrenceDayKey(occurrenceDate): ScheduledOccurrenceState(
        scheduledDate: occurrenceDate,
        plannedAmountMinor: 20000,
        status: ScheduledOccurrenceStatus.pending,
        revision: 0,
        operationId: 'legacy-pending',
        changedAt: DateTime.utc(2026, 8, 1),
        deviceId: 'legacy',
      ).toJson()..['status'] = 'unknown-future-status',
    };

    expect(
      () => const BackupRestoreValidator().validate(jsonEncode(raw)),
      throwsA(isA<BackupValidationException>()),
    );
  });

  test(
    'strict restore rejects Paid Fund links with mismatched causal data',
    () async {
      final store = _store(occurrenceDate);
      await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );
      final corruptions = <void Function(Map<String, Object?>)>[
        (raw) => _rawReservationOperations(raw).single['amountMinor'] = 19999,
        (raw) =>
            _rawReservationOperations(raw).single['containerId'] = 'other-fund',
        (raw) =>
            _rawReservationOperations(raw).single['scheduledOccurrenceDate'] =
                DateTime(2026, 8, 25).toIso8601String(),
        (raw) => _rawReservationOperations(raw).single['effectiveDate'] =
            DateTime(2026, 8, 25).toIso8601String(),
        (raw) {
          final state = _rawOccurrenceStates(raw).single
            ..['reservationOperationId'] = null;
          _rawSchedules(raw).single['occurrenceStates'] = <String, Object?>{
            occurrenceDayKey(occurrenceDate): state,
          };
        },
      ];

      for (final corrupt in corruptions) {
        final raw = _backupMap(store.dataSet);
        corrupt(raw);
        expect(
          () => const BackupRestoreValidator().validate(jsonEncode(raw)),
          throwsA(isA<BackupValidationException>()),
        );
      }
    },
  );

  test(
    'strict restore requires Pending Undo to reverse the matching allocation',
    () async {
      final store = _store(occurrenceDate);
      await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );
      await store.undoScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
      );

      expect(
        const BackupRestoreValidator()
            .validate(const BackupCodec().encodeJson(store.dataSet))
            .dataSet
            .reservationOperations,
        hasLength(2),
      );

      final wrongAmount = _backupMap(store.dataSet);
      _rawReservationOperations(wrongAmount).firstWhere(
        (item) => item['kind'] == ReservationOperationKind.reversal.name,
      )['amountMinor'] = 19999;
      expect(
        () => const BackupRestoreValidator().validate(jsonEncode(wrongAmount)),
        throwsA(isA<BackupValidationException>()),
      );

      final wrongStateLink = _backupMap(store.dataSet);
      final allocationId = _rawReservationOperations(wrongStateLink).firstWhere(
        (item) => item['kind'] == ReservationOperationKind.allocate.name,
      )['id'];
      _rawOccurrenceStates(wrongStateLink).single['reservationOperationId'] =
          allocationId;
      expect(
        () =>
            const BackupRestoreValidator().validate(jsonEncode(wrongStateLink)),
        throwsA(isA<BackupValidationException>()),
      );

      final wrongReversalDate = _backupMap(store.dataSet);
      _rawReservationOperations(wrongReversalDate).firstWhere(
        (item) => item['kind'] == ReservationOperationKind.reversal.name,
      )['effectiveDate'] = DateTime(
        2026,
        8,
        25,
      ).toIso8601String();
      expect(
        () => const BackupRestoreValidator().validate(
          jsonEncode(wrongReversalDate),
        ),
        throwsA(isA<BackupValidationException>()),
      );
    },
  );

  test(
    'completing scheduled Fund funding allocates exactly once without a transaction',
    () async {
      final store = _store(occurrenceDate);
      final startingBalance = store.balanceForAccount('checking');
      final startingNetWorth = store.netWorthMinor;

      final first = await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );
      final retried = await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );

      expect(retried.id, first.id);
      expect(first.containerType, ReservationContainerType.fund);
      expect(first.containerId, 'bills');
      expect(first.fundingAccountId, 'checking');
      expect(first.kind, ReservationOperationKind.allocate);
      expect(first.amountMinor, 20000);
      expect(first.scheduledTransactionId, 'scheduled-bills-funding');
      expect(first.scheduledOccurrenceDate, occurrenceDate);
      expect(store.transactions, isEmpty);
      expect(store.reservationOperations, hasLength(1));
      expect(store.currentFundAmountMinor('bills'), 20000);
      expect(store.availableToSpendForAccount('checking'), 480000);
      expect(store.balanceForAccount('checking'), startingBalance);
      expect(store.netWorthMinor, startingNetWorth);

      final occurrence = store
          .scheduledTransactions
          .single
          .occurrenceStates[occurrenceDayKey(occurrenceDate)];
      expect(occurrence?.status, ScheduledOccurrenceStatus.paid);
      expect(occurrence?.reservationOperationId, first.id);
    },
  );

  test(
    'Undo scheduled Fund funding reverses once and reopens occurrence',
    () async {
      final store = _store(occurrenceDate);
      final startingBalance = store.balanceForAccount('checking');
      final startingNetWorth = store.netWorthMinor;
      final allocation = await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );
      final paidState = store
          .scheduledTransactions
          .single
          .occurrenceStates[occurrenceDayKey(occurrenceDate)]!;

      await store.undoScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
      );

      final reversals = store.reservationOperations.where(
        (operation) =>
            operation.kind == ReservationOperationKind.reversal &&
            operation.reversesOperationId == allocation.id,
      );
      expect(reversals, hasLength(1));
      expect(store.currentFundAmountMinor('bills'), 0);
      expect(store.availableToSpendForAccount('checking'), 500000);
      expect(store.balanceForAccount('checking'), startingBalance);
      expect(store.netWorthMinor, startingNetWorth);
      expect(store.transactions, isEmpty);

      final reopened = store
          .scheduledTransactions
          .single
          .occurrenceStates[occurrenceDayKey(occurrenceDate)]!;
      expect(reopened.status, ScheduledOccurrenceStatus.pending);
      expect(reopened.revision, greaterThan(paidState.revision));
      expect(
        store.scheduledTransactions.single.nextDate,
        DateTime(2026, 8, 24),
      );
    },
  );

  test('skipping scheduled Fund funding allocates nothing', () async {
    final store = _store(occurrenceDate);
    final schedule = store.scheduledTransactions.single;

    await recordScheduledOccurrence(
      store,
      schedule,
      ScheduledAction.skipped,
      occurrence: ScheduledOccurrenceRecord(
        scheduledDate: occurrenceDate,
        plannedAmountMinor: schedule.amountMinor,
        status: ScheduledOccurrenceStatus.skipped,
      ),
    );

    expect(store.reservationOperations, isEmpty);
    expect(store.transactions, isEmpty);
    expect(store.currentFundAmountMinor('bills'), 0);
    expect(store.balanceForAccount('checking'), 500000);
    expect(store.netWorthMinor, 500000);
    expect(
      store
          .scheduledTransactions
          .single
          .occurrenceStates[occurrenceDayKey(occurrenceDate)]
          ?.status,
      ScheduledOccurrenceStatus.skipped,
    );
    expect(store.scheduledTransactions.single.nextDate, DateTime(2026, 9, 24));
  });

  test(
    'ordinary scheduled expense still creates one real transaction',
    () async {
      final store = _store(occurrenceDate);
      final ordinary = ScheduledTransactionRecord(
        id: 'scheduled-rent',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'rent',
        payee: 'Landlord',
        amountMinor: 10000,
        nextDate: occurrenceDate,
        frequency: RecurrenceFrequency.monthly,
        sync: SyncMetadata.fresh(
          now: DateTime.utc(2026, 8, 1),
          deviceId: 'device-a',
        ),
      );
      await store.saveScheduledTransaction(ordinary);

      final first = await completeScheduledTransactionPayment(
        store,
        ordinary,
        actualAmountMinor: 10000,
        paymentDate: occurrenceDate,
        payee: ordinary.payee,
        note: '',
      );
      final retried = await completeScheduledTransactionPayment(
        store,
        ordinary,
        actualAmountMinor: 10000,
        paymentDate: occurrenceDate,
        payee: ordinary.payee,
        note: '',
      );

      expect(retried.id, first.id);
      expect(store.transactions, hasLength(1));
      expect(store.transactions.single.type, TransactionType.expense);
      expect(store.balanceForAccount('checking'), 490000);
      expect(store.netWorthMinor, 490000);
      expect(store.reservationOperations, isEmpty);
      expect(store.currentFundAmountMinor('bills'), 0);
    },
  );
}

FinanceDataStore _store(DateTime occurrenceDate) {
  final sync = SyncMetadata.fresh(
    now: DateTime.utc(2026, 8, 1),
    deviceId: 'device-a',
  );
  return FinanceDataStore(
    deviceId: 'device-a',
    dataSet: FinanceDataSet(
      accounts: [
        AccountRecord(
          id: 'checking',
          name: 'CTBI',
          type: AccountType.checking,
          openingBalanceMinor: 500000,
          sync: sync,
        ),
      ],
      categories: [
        CategoryRecord(
          id: 'rent',
          name: 'Rent',
          kind: CategoryKind.expense,
          sync: sync,
        ),
      ],
      transactions: const [],
      scheduledTransactions: [_schedule(occurrenceDate, sync: sync)],
      budgets: const [],
      goals: const [],
      funds: [
        FundRecord(
          id: 'bills',
          name: 'Bills',
          fundingAccountId: 'checking',
          status: FundStatus.active,
          targetBalanceMinor: 300000,
          sync: sync,
        ),
      ],
      reservationOperations: const [],
      preferences: const UserPreferences(),
    ),
  );
}

ScheduledTransactionRecord _schedule(
  DateTime occurrenceDate, {
  SyncMetadata? sync,
}) {
  return ScheduledTransactionRecord(
    id: 'scheduled-bills-funding',
    type: TransactionType.goalFunding,
    accountId: 'checking',
    payee: 'Bills funding',
    amountMinor: 20000,
    nextDate: occurrenceDate,
    frequency: RecurrenceFrequency.monthly,
    reservationFundingContainerType: ReservationContainerType.fund,
    reservationFundingContainerId: 'bills',
    sync:
        sync ??
        SyncMetadata.fresh(now: DateTime.utc(2026, 8, 1), deviceId: 'device-a'),
  );
}

Map<String, Object?> _backupMap(FinanceDataSet dataSet) =>
    Map<String, Object?>.from(
      jsonDecode(const BackupCodec().encodeJson(dataSet)) as Map,
    );

List<Map<String, Object?>> _rawRecords(
  Map<String, Object?> raw,
  String collection,
) => (raw[collection]! as List<Object?>)
    .map((item) => Map<String, Object?>.from(item! as Map))
    .toList(growable: false);

List<Map<String, Object?>> _rawSchedules(Map<String, Object?> raw) {
  final records = _rawRecords(raw, 'scheduledTransactions');
  raw['scheduledTransactions'] = records;
  return records;
}

List<Map<String, Object?>> _rawFunds(Map<String, Object?> raw) {
  final records = _rawRecords(raw, 'funds');
  raw['funds'] = records;
  return records;
}

List<Map<String, Object?>> _rawAccounts(Map<String, Object?> raw) {
  final records = _rawRecords(raw, 'accounts');
  raw['accounts'] = records;
  return records;
}

List<Map<String, Object?>> _rawReservationOperations(Map<String, Object?> raw) {
  final records = _rawRecords(raw, 'reservationOperations');
  raw['reservationOperations'] = records;
  return records;
}

List<Map<String, Object?>> _rawOccurrenceStates(Map<String, Object?> raw) {
  final schedule = _rawSchedules(raw).single;
  final states = Map<String, Object?>.from(
    schedule['occurrenceStates']! as Map,
  );
  for (final entry in states.entries.toList(growable: false)) {
    states[entry.key] = Map<String, Object?>.from(entry.value! as Map);
  }
  schedule['occurrenceStates'] = states;
  return states.values.cast<Map<String, Object?>>().toList(growable: false);
}
