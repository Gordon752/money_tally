import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  final day = DateTime(2020, 1, 15);

  test(
    'one exact batch creates independently revisioned Fund allocations',
    () async {
      final local = _RecordingLocalRepository();
      final store = _store(localRepository: local);

      final operations = await store.allocateFunds(
        sourceAccountId: 'checking',
        totalAmountMinor: 120000,
        date: day,
        allocations: const [
          FundAllocation(fundId: 'bills', amountMinor: 70000),
          FundAllocation(fundId: 'repairs', amountMinor: 50000),
        ],
        note: '  Monthly reserves  ',
      );

      expect(operations, hasLength(2));
      expect(operations.map((operation) => operation.containerId), [
        'bills',
        'repairs',
      ]);
      expect(operations.map((operation) => operation.amountMinor), [
        70000,
        50000,
      ]);
      expect(
        operations,
        everyElement(
          isA<ReservationOperationRecord>()
              .having(
                (operation) => operation.containerType,
                'container type',
                ReservationContainerType.fund,
              )
              .having(
                (operation) => operation.kind,
                'kind',
                ReservationOperationKind.allocate,
              )
              .having(
                (operation) => operation.fundingAccountId,
                'funding account',
                'checking',
              )
              .having((operation) => operation.baseRevision, 'base', 0)
              .having((operation) => operation.revision, 'revision', 1)
              .having(
                (operation) => operation.note,
                'note',
                'Monthly reserves',
              ),
        ),
      );
      expect(
        operations.map((operation) {
          final causationId = operation.causationId!;
          return causationId.substring(0, causationId.lastIndexOf(':'));
        }).toSet(),
        hasLength(1),
      );
      expect(store.currentFundAmountMinor('bills', asOf: day), 70000);
      expect(store.currentFundAmountMinor('repairs', asOf: day), 50000);
      expect(store.availableToSpendForAccount('checking', asOf: day), 380000);
      expect(local.saveCount, 1);
      expect(local.savedDataSet?.reservationOperations, hasLength(2));
    },
  );

  test('each Fund advances from its own latest revision', () async {
    final store = _store(
      initialOperations: [
        _operation(
          id: 'existing-bills',
          fundId: 'bills',
          amountMinor: 10000,
          revision: 1,
          day: day,
        ),
      ],
    );

    final operations = await store.allocateFunds(
      sourceAccountId: 'checking',
      totalAmountMinor: 30000,
      date: day,
      allocations: const [
        FundAllocation(fundId: 'bills', amountMinor: 20000),
        FundAllocation(fundId: 'repairs', amountMinor: 10000),
      ],
    );

    final bills = operations.singleWhere(
      (operation) => operation.containerId == 'bills',
    );
    final repairs = operations.singleWhere(
      (operation) => operation.containerId == 'repairs',
    );
    expect((bills.baseRevision, bills.revision), (1, 2));
    expect((repairs.baseRevision, repairs.revision), (0, 1));
  });

  test('invalid batch is rejected without partial operations', () async {
    final store = _store();

    await expectLater(
      store.allocateFunds(
        sourceAccountId: 'checking',
        totalAmountMinor: 30000,
        date: day,
        allocations: const [
          FundAllocation(fundId: 'bills', amountMinor: 20000),
          FundAllocation(fundId: 'repairs', amountMinor: 9000),
        ],
      ),
      throwsA(isA<FinanceDataValidationException>()),
    );
    await expectLater(
      store.allocateFunds(
        sourceAccountId: 'checking',
        totalAmountMinor: 30000,
        date: day,
        allocations: const [
          FundAllocation(fundId: 'bills', amountMinor: 20000),
          FundAllocation(fundId: 'bills', amountMinor: 10000),
        ],
      ),
      throwsA(isA<FinanceDataValidationException>()),
    );
    await expectLater(
      store.allocateFunds(
        sourceAccountId: 'checking',
        totalAmountMinor: 30000,
        date: day,
        allocations: const [
          FundAllocation(fundId: 'savings-fund', amountMinor: 30000),
        ],
      ),
      throwsA(isA<FinanceDataValidationException>()),
    );

    expect(store.reservationOperations, isEmpty);
  });

  test('available money is validated across the whole batch', () async {
    final store = _store();

    await expectLater(
      store.allocateFunds(
        sourceAccountId: 'checking',
        totalAmountMinor: 500001,
        date: day,
        allocations: const [
          FundAllocation(fundId: 'bills', amountMinor: 250001),
          FundAllocation(fundId: 'repairs', amountMinor: 250000),
        ],
      ),
      throwsA(isA<FinanceDataValidationException>()),
    );
    expect(store.reservationOperations, isEmpty);
  });

  test('local save failure rolls back the complete batch', () async {
    final store = _store(localRepository: _FailingLocalRepository());

    await expectLater(
      store.allocateFunds(
        sourceAccountId: 'checking',
        totalAmountMinor: 30000,
        date: day,
        allocations: const [
          FundAllocation(fundId: 'bills', amountMinor: 20000),
          FundAllocation(fundId: 'repairs', amountMinor: 10000),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    expect(store.reservationOperations, isEmpty);
    expect(store.currentFundAmountMinor('bills', asOf: day), 0);
    expect(store.currentFundAmountMinor('repairs', asOf: day), 0);
  });
}

FinanceDataStore _store({
  LocalFinanceDataSetRepository? localRepository,
  List<ReservationOperationRecord> initialOperations = const [],
}) {
  final sync = SyncMetadata.fresh(
    now: DateTime(2020, 1, 1),
    deviceId: 'device-a',
  );
  return FinanceDataStore(
    deviceId: 'device-a',
    localRepository: localRepository,
    dataSet: FinanceDataSet(
      accounts: [
        AccountRecord(
          id: 'checking',
          name: 'Checking',
          type: AccountType.checking,
          openingBalanceMinor: 500000,
          sync: sync,
        ),
        AccountRecord(
          id: 'savings',
          name: 'Savings',
          type: AccountType.savings,
          openingBalanceMinor: 100000,
          sync: sync,
        ),
      ],
      categories: const [],
      transactions: const [],
      scheduledTransactions: const [],
      budgets: const [],
      funds: [
        FundRecord(
          id: 'bills',
          name: 'Bills',
          fundingAccountId: 'checking',
          status: FundStatus.active,
          sync: sync,
        ),
        FundRecord(
          id: 'repairs',
          name: 'Repairs',
          fundingAccountId: 'checking',
          status: FundStatus.active,
          sync: sync,
        ),
        FundRecord(
          id: 'savings-fund',
          name: 'Savings Fund',
          fundingAccountId: 'savings',
          status: FundStatus.active,
          sync: sync,
        ),
      ],
      reservationOperations: initialOperations,
      preferences: const UserPreferences(),
    ),
  );
}

ReservationOperationRecord _operation({
  required String id,
  required String fundId,
  required int amountMinor,
  required int revision,
  required DateTime day,
}) {
  return ReservationOperationRecord(
    id: id,
    containerType: ReservationContainerType.fund,
    containerId: fundId,
    fundingAccountId: 'checking',
    kind: ReservationOperationKind.allocate,
    amountMinor: amountMinor,
    effectiveDate: day,
    revision: revision,
    baseRevision: revision - 1,
    operationId: id,
    deviceId: 'device-a',
    sync: SyncMetadata.fresh(now: day, deviceId: 'device-a'),
  );
}

class _RecordingLocalRepository extends LocalFinanceDataSetRepository {
  int saveCount = 0;
  FinanceDataSet? savedDataSet;

  @override
  Future<void> save(FinanceDataSet dataSet) async {
    saveCount += 1;
    savedDataSet = dataSet;
  }
}

class _FailingLocalRepository extends LocalFinanceDataSetRepository {
  @override
  Future<void> save(FinanceDataSet dataSet) async {
    throw StateError('Local save failed.');
  }
}
