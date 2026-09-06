import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_restore_service.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final scenario in [
    (
      anchor: DateTime(2026, 9, 30),
      month: DateTime(2026, 10),
      fixed: 30,
      eom: 31,
    ),
    (
      anchor: DateTime(2027, 1, 31),
      month: DateTime(2027, 2),
      fixed: 28,
      eom: 28,
    ),
    (
      anchor: DateTime(2028, 1, 31),
      month: DateTime(2028, 2),
      fixed: 29,
      eom: 29,
    ),
    (
      anchor: DateTime(2027, 2, 28),
      month: DateTime(2027, 3),
      fixed: 28,
      eom: 31,
    ),
    (
      anchor: DateTime(2028, 2, 29),
      month: DateTime(2028, 3),
      fixed: 29,
      eom: 31,
    ),
    (
      anchor: DateTime(2026, 4, 30),
      month: DateTime(2026, 5),
      fixed: 30,
      eom: 31,
    ),
    (
      anchor: DateTime(2026, 12, 31),
      month: DateTime(2027, 1),
      fixed: 31,
      eom: 31,
    ),
    (
      anchor: DateTime(2027, 1, 31),
      month: DateTime(2027, 3),
      fixed: 31,
      eom: 31,
    ),
    (
      anchor: DateTime(2027, 1, 30),
      month: DateTime(2027, 3),
      fixed: 30,
      eom: 31,
    ),
    (
      anchor: DateTime(2026, 9, 15),
      month: DateTime(2026, 10),
      fixed: 15,
      eom: 31,
    ),
  ]) {
    for (final rule in FundTargetDayRule.values) {
      test('$rule from ${scenario.anchor} to ${scenario.month}', () {
        final fund = _fund(scenario.anchor, rule: rule);
        final expected = DateTime(
          scenario.month.year,
          scenario.month.month,
          rule == FundTargetDayRule.endOfMonth ? scenario.eom : scenario.fixed,
        );
        expect(effectiveFundTargetDate(fund, asOf: scenario.month), expected);
        expect(
          fundTargetBoundary(fund, year: expected.year, month: expected.month),
          expected,
        );
        // Repeated derivation never advances the stored anchor or changes money.
        expect(effectiveFundTargetDate(fund, asOf: scenario.month), expected);
        expect(fund.nextTargetDate, scenario.anchor);
        expect(fund.targetBalanceMinor, 360000);
      });
    }
  }

  test('month-end sequence remains anchored across months and years', () {
    final fund = _fund(
      DateTime(2026, 9, 30),
      rule: FundTargetDayRule.endOfMonth,
    );
    expect(
      [
        for (var month = 9; month <= 14; month++)
          fundTargetBoundary(fund, year: 2026, month: month),
      ],
      [
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 30),
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 31),
        DateTime(2027, 2, 28),
      ],
    );
    expect(
      fundTargetBoundary(fund, year: 2026, month: 8),
      DateTime(2026, 8, 31),
    );
  });

  test('legacy month-end dates are fixed-day, with no intent inference', () {
    for (final date in [DateTime(2026, 9, 30), DateTime(2027, 2, 28)]) {
      final json = _fund(date).toJson()..remove('targetDayRule');
      final fund = FundRecord.fromJson(json);
      expect(fund.targetDayRule, FundTargetDayRule.fixedDay);
      expect(
        effectiveFundTargetDate(
          fund,
          asOf: DateTime(date.year, date.month + 1),
        ),
        DateTime(date.year, date.month + 1, date.day),
      );
    }
  });

  test('rule survives JSON and unrelated edits', () {
    final original = _fund(
      DateTime(2026, 9, 30),
      rule: FundTargetDayRule.endOfMonth,
    );
    final reloaded = FundRecord.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
    );
    expect(reloaded.toJson(), original.toJson());
    expect(
      reloaded.copyWith(name: 'Utilities').targetDayRule,
      FundTargetDayRule.endOfMonth,
    );
    expect(
      reloaded
          .copyWith(targetDayRule: FundTargetDayRule.fixedDay)
          .nextTargetDate,
      original.nextTargetDate,
    );
  });

  test(
    'boundaries use local calendar dates, including the whole target day',
    () {
      final original = _fund(
        DateTime(2026, 9, 30),
        rule: FundTargetDayRule.endOfMonth,
      );
      final fund = FundRecord.fromJson(original.toJson());
      expect(fund.nextTargetDate!.isUtc, isFalse);
      final boundary = effectiveFundTargetDate(
        fund,
        asOf: DateTime(2026, 10, 31, 23, 59),
      )!;
      expect(boundary, DateTime(2026, 10, 31));
      expect(boundary.isUtc, isFalse);
      expect(
        effectiveFundTargetDate(fund, asOf: DateTime(2026, 11, 1)),
        DateTime(2026, 11, 30),
      );
    },
  );

  test('no recurring target still has no recurring boundary', () {
    final fund = _fund(
      DateTime(2026, 9, 30),
    ).copyWith(targetCadence: FundTargetCadence.none);
    expect(effectiveFundTargetDate(fund), isNull);
    expect(fundTargetBoundary(fund, year: 2026, month: 10), isNull);
  });

  test(
    'current schema preserves both rules through backup restore and local storage',
    () async {
      SharedPreferences.setMockInitialValues({});
      final original = _dataSet();
      final raw = const BackupCodec().encodeJson(original);
      expect((jsonDecode(raw) as Map)['schemaVersion'], 7);
      expect(currentBackupSchemaVersion, 7);
      final validated = const BackupRestoreValidator().validate(raw);
      expect(validated.dataSet.toJson(), original.toJson());
      const local = LocalFinanceDataSetRepository(
        storageKey: 'fund-rule-roundtrip',
      );
      await local.save(validated.dataSet);
      expect((await local.load())!.toJson(), original.toJson());
    },
  );

  test(
    'schema 5 migration preserves dates and explicitly assigns fixed-day',
    () {
      final original = _dataSet().toJson();
      final funds = (original['funds'] as List).cast<Map<String, Object?>>();
      for (final fund in funds) {
        fund.remove('targetDayRule');
      }
      original['schemaVersion'] = 5;
      final validated = const BackupRestoreValidator().validate(
        jsonEncode(original),
      );
      expect(validated.sourceSchemaVersion, 5);
      expect(validated.schemaVersion, 7);
      for (final fund in validated.dataSet.funds) {
        expect(fund.targetDayRule, FundTargetDayRule.fixedDay);
        expect(fund.nextTargetDate, DateTime(2026, 9, 30));
        expect(
          effectiveFundTargetDate(fund, asOf: DateTime(2026, 10, 1)),
          DateTime(2026, 10, 30),
        );
      }
    },
  );

  for (final invalidRule in [null, 'inferMonthEnd', 1]) {
    test('schema 6 rejects invalid or missing timing rule: $invalidRule', () {
      final raw = _dataSet().toJson();
      final fund = (raw['funds'] as List).first as Map<String, Object?>;
      if (invalidRule == null) {
        fund.remove('targetDayRule');
      } else {
        fund['targetDayRule'] = invalidRule;
      }
      expect(
        () => const BackupRestoreValidator().validate(jsonEncode(raw)),
        throwsA(isA<BackupValidationException>()),
      );
    });
  }
}

FundRecord _fund(
  DateTime date, {
  FundTargetDayRule rule = FundTargetDayRule.fixedDay,
}) => FundRecord(
  id: rule.name,
  name: 'Bills',
  fundingAccountId: 'checking',
  status: FundStatus.active,
  targetBalanceMinor: 360000,
  targetCadence: FundTargetCadence.monthly,
  targetDayRule: rule,
  nextTargetDate: date,
  sync: SyncMetadata.fresh(now: DateTime.utc(2026, 9, 4)),
);

FinanceDataSet _dataSet() => FinanceDataSet(
  accounts: [
    AccountRecord(
      id: 'checking',
      name: 'CTBI',
      type: AccountType.checking,
      openingBalanceMinor: 1000000,
      sync: SyncMetadata.fresh(now: DateTime.utc(2026, 9, 4)),
    ),
  ],
  categories: const [],
  transactions: const [],
  scheduledTransactions: const [],
  budgets: const [],
  funds: [
    for (final rule in FundTargetDayRule.values)
      _fund(DateTime(2026, 9, 30), rule: rule),
  ],
  preferences: const UserPreferences(),
);
