import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/persistence/local_finance_data_structure.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';

const _required = [
  'accounts',
  'categories',
  'transactions',
  'scheduledTransactions',
  'budgets',
];
const _optional = [
  'goals',
  'funds',
  'reservationOperations',
  'goalContributions',
  'goalFundingEvents',
];
Map<String, Object?> _legacy() => {
  for (final key in _required) key: <Object?>[],
  'preferences': <String, Object?>{},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const repository = LocalFinanceDataSetRepository();
  Future<void> rejected(Map<String, Object?> json) async {
    final raw = jsonEncode(json);
    SharedPreferences.setMockInitialValues({repository.storageKey: raw});
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        repository.load(),
        throwsA(
          isA<UnreadableLocalFinanceData>().having(
            (e) => e.original,
            'original',
            raw,
          ),
        ),
      );
      expect(await repository.readRaw(), raw);
    }
  }

  for (final key in [..._required, ..._optional]) {
    for (final value in [
      null,
      42,
      'bad',
      <String, Object?>{},
      [null],
    ]) {
      test(
        'rejects malformed $key: $value without writing',
        () => rejected({..._legacy(), key: value}),
      );
    }
  }
  for (final key in [..._required, 'preferences']) {
    test(
      'missing core $key is not an empty dataset',
      () => rejected(_legacy()..remove(key)),
    );
  }
  test(
    'invalid preferences do not silently reset settings',
    () => rejected({..._legacy(), 'preferences': []}),
  );
  test(
    'older records may omit later collections and preference fields',
    () async {
      final raw = jsonEncode(_legacy());
      SharedPreferences.setMockInitialValues({repository.storageKey: raw});
      final data = await repository.load();
      expect(data, isNotNull);
      expect(data!.accounts, isEmpty);
      expect(data.funds, isEmpty);
      expect(await repository.readRaw(), raw);
    },
  );
  test('genuinely absent data remains a fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await repository.load(), isNull);
  });
  for (final entry in {
    'transactions': ['splitLines'],
    'scheduledTransactions': [
      'splitLines',
      'goalFundingAllocations',
      'occurrences',
      'occurrenceStates',
    ],
    'budgets': ['configurationRevisions'],
    'goalFundingEvents': ['allocations'],
  }.entries) {
    for (final field in entry.value) {
      test('rejects malformed nested ${entry.key}.$field', () async {
        final record = <String, Object?>{
          'id': 'record',
          'sync': <String, Object?>{},
        };
        final json = {
          ..._legacy(),
          entry.key: [record],
        };
        validateLocalFinanceDataStructure(json);
        record[field] = 42;
        expect(
          () => validateLocalFinanceDataStructure(json),
          throwsFormatException,
        );
        await rejected(json);
      });
    }
  }
  test(
    'populated legacy data retains balances and absent newer defaults',
    () async {
      final account = AccountRecord(
        id: 'legacy',
        name: 'Wallet',
        type: AccountType.cash,
        openingBalanceMinor: 12345,
        sync: SyncMetadata.fresh(),
      );
      final json = {
        ..._legacy(),
        'accounts': [account.toJson()],
        'unknownFutureField': {'keep': true},
      };
      final raw = jsonEncode(json);
      SharedPreferences.setMockInitialValues({repository.storageKey: raw});
      final loaded = (await repository.load())!;
      expect(loaded.accounts.single.toJson(), account.toJson());
      expect(loaded.balanceForAccount('legacy'), 12345);
      expect(await repository.readRaw(), raw);
    },
  );
}
