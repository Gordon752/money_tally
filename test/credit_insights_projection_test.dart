import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/credit/credit_insights_calculator.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';

void main() {
  const calculator = CreditInsightsCalculator();

  group('Credit Insights end-of-cycle projection', () {
    test('constant balance projects every day in a full cycle', () {
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -100000),
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 8, 10),
      );

      // 31 days × $1,000 debt × 0.1% daily rate = $31 interest.
      expect(estimate.averageDailyBalanceMinor, 100000);
      expect(estimate.estimatedInterestMinor, 3100);
      expect(estimate.projectedStatementMinor, -103100);
      expect(estimate.daysRepresented, 10);
      expect(estimate.totalCycleDays, 31);
    });

    test('mid-cycle purchase is carried through closing', () {
      final purchase = _transaction(
        id: 'purchase',
        type: TransactionType.expense,
        date: DateTime(2026, 8, 16),
        amountMinor: 50000,
      );
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -100000),
        transactions: [purchase],
        currentBalanceMinor: -150000,
        today: DateTime(2026, 8, 16),
      );

      // 15 × $1,000 + 16 × $1,500 = $39,000 balance-days.
      expect(estimate.averageDailyBalanceMinor, closeTo(125806.45, 0.01));
      expect(estimate.estimatedInterestMinor, 3900);
      expect(estimate.projectedStatementMinor, -153900);
    });

    test('mid-cycle payment lowers projected remaining balance', () {
      final payment = _payment(
        id: 'payment',
        date: DateTime(2026, 8, 16),
        amountMinor: 50000,
      );
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -200000),
        transactions: [payment],
        currentBalanceMinor: -150000,
        today: DateTime(2026, 8, 16),
      );

      // 15 × $2,000 + 16 × $1,500 = $54,000 balance-days.
      expect(estimate.averageDailyBalanceMinor, closeTo(174193.55, 0.01));
      expect(estimate.estimatedInterestMinor, 5400);
      expect(estimate.projectedStatementMinor, -155400);
    });

    test('mid-cycle refund or credit lowers the projection', () {
      final refund = _transaction(
        id: 'refund',
        type: TransactionType.income,
        date: DateTime(2026, 8, 16),
        amountMinor: 20000,
      );
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -100000),
        transactions: [refund],
        currentBalanceMinor: -80000,
        today: DateTime(2026, 8, 16),
      );

      // 15 × $1,000 + 16 × $800 = $27,800 balance-days.
      expect(estimate.averageDailyBalanceMinor, closeTo(89677.42, 0.01));
      expect(estimate.estimatedInterestMinor, 2780);
      expect(estimate.projectedStatementMinor, -82780);
    });

    test('multiple balance changes use historical facts then current debt', () {
      final transactions = [
        _transaction(
          id: 'purchase',
          type: TransactionType.expense,
          date: DateTime(2026, 8, 3),
          amountMinor: 50000,
        ),
        _payment(id: 'payment', date: DateTime(2026, 8, 5), amountMinor: 25000),
        _transaction(
          id: 'refund',
          type: TransactionType.income,
          date: DateTime(2026, 8, 7),
          amountMinor: 10000,
        ),
      ];
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -100000),
        transactions: transactions,
        currentBalanceMinor: -115000,
        today: DateTime(2026, 8, 8),
      );

      // 2×1000 + 2×1500 + 2×1250 + 25×1150 = $36,250.
      expect(estimate.averageDailyBalanceMinor, closeTo(116935.48, 0.01));
      expect(estimate.estimatedInterestMinor, 3625);
      expect(estimate.projectedStatementMinor, -118625);
    });

    test('consecutive no-activity days keep the projection stable', () {
      final account = _account(openingBalanceMinor: -100000);
      final august10 = calculator.calculate(
        account: account,
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 8, 10),
      );
      final august11 = calculator.calculate(
        account: account,
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 8, 11),
      );

      expect(
        august11.averageDailyBalanceMinor,
        august10.averageDailyBalanceMinor,
      );
      expect(august11.estimatedInterestMinor, august10.estimatedInterestMinor);
      expect(
        august11.projectedStatementMinor,
        august10.projectedStatementMinor,
      );
    });

    test('paying to zero retains interest from earlier cycle debt', () {
      final payment = _payment(
        id: 'pay-in-full',
        date: DateTime(2026, 8, 16),
        amountMinor: 100000,
      );
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -100000),
        transactions: [payment],
        currentBalanceMinor: 0,
        today: DateTime(2026, 8, 16),
      );

      expect(estimate.estimatedInterestMinor, 1500);
      expect(estimate.projectedStatementMinor, -1500);
    });

    test('new purchase after paying to zero restarts projected debt', () {
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -100000),
        transactions: [
          _payment(
            id: 'pay-in-full',
            date: DateTime(2026, 8, 16),
            amountMinor: 100000,
          ),
          _transaction(
            id: 'new-purchase',
            type: TransactionType.expense,
            date: DateTime(2026, 8, 20),
            amountMinor: 30000,
          ),
        ],
        currentBalanceMinor: -30000,
        today: DateTime(2026, 8, 20),
      );

      expect(estimate.estimatedInterestMinor, 1860);
      expect(estimate.projectedStatementMinor, -31860);
    });

    test('partial first cycle projects only reliable and future days', () {
      final estimate = calculator.calculate(
        account: _account(
          openingBalanceMinor: -100000,
          createdAt: DateTime(2026, 8, 10),
        ),
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 8, 20),
      );

      expect(estimate.representedStart, DateTime(2026, 8, 10));
      expect(estimate.daysRepresented, 11);
      expect(estimate.averageDailyBalanceMinor, 100000);
      expect(estimate.estimatedInterestMinor, 2200);
      expect(
        estimate.estimateCompleteness,
        CreditInsightsEstimateCompleteness.partial,
      );
    });

    test('partial clears when the next fully known cycle begins', () {
      final estimate = calculator.calculate(
        account: _account(
          openingBalanceMinor: -100000,
          createdAt: DateTime(2026, 8, 10),
        ),
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 9, 1),
      );

      expect(estimate.cycleStart, DateTime(2026, 9, 1));
      expect(estimate.cycleEnd, DateTime(2026, 9, 30));
      expect(estimate.estimatedInterestMinor, 3000);
      expect(
        estimate.estimateCompleteness,
        CreditInsightsEstimateCompleteness.complete,
      );
    });

    test('closing day 31 clamps to a 30-day month', () {
      final estimate = calculator.calculate(
        account: _account(
          openingBalanceMinor: -100000,
          createdAt: DateTime(2025, 1, 1),
        ),
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 4, 15),
      );

      expect(estimate.cycleStart, DateTime(2026, 4, 1));
      expect(estimate.cycleEnd, DateTime(2026, 4, 30));
      expect(estimate.estimatedInterestMinor, 3000);
    });

    test('February projection handles an ordinary year', () {
      final estimate = calculator.calculate(
        account: _account(
          openingBalanceMinor: -100000,
          createdAt: DateTime(2025, 1, 1),
        ),
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 2, 10),
      );

      expect(estimate.cycleEnd, DateTime(2026, 2, 28));
      expect(estimate.estimatedInterestMinor, 2800);
    });

    test('February projection handles a leap year', () {
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -100000),
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2028, 2, 10),
      );

      expect(estimate.cycleEnd, DateTime(2028, 2, 29));
      expect(estimate.estimatedInterestMinor, 2900);
    });

    test('transaction on statement closing date affects that cycle', () {
      final purchase = _transaction(
        id: 'closing-purchase',
        type: TransactionType.expense,
        date: DateTime(2026, 8, 31, 17),
        amountMinor: 50000,
      );
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -100000),
        transactions: [purchase],
        currentBalanceMinor: -150000,
        today: DateTime(2026, 8, 31),
      );

      expect(estimate.estimatedInterestMinor, 3150);
      expect(estimate.projectedStatementMinor, -153150);
    });

    test('transaction after closing does not leak into current cycle', () {
      final futurePurchase = _transaction(
        id: 'next-cycle-purchase',
        type: TransactionType.expense,
        date: DateTime(2026, 8, 16),
        amountMinor: 50000,
      );
      final estimate = calculator.calculate(
        account: _account(
          openingBalanceMinor: -100000,
          statementClosingDay: 15,
        ),
        transactions: [futurePurchase],
        // Ordinary Trackmark balance semantics already include the record.
        currentBalanceMinor: -150000,
        today: DateTime(2026, 8, 15),
      );

      expect(estimate.cycleEnd, DateTime(2026, 8, 15));
      expect(estimate.averageDailyBalanceMinor, 100000);
      expect(estimate.estimatedInterestMinor, 3100);
      expect(estimate.projectedStatementMinor, -103100);
    });

    test(
      'future pending transaction starts affecting projection on its date',
      () {
        final futurePurchase = _transaction(
          id: 'future-pending',
          type: TransactionType.expense,
          date: DateTime(2026, 8, 20),
          amountMinor: 50000,
          status: TransactionStatus.pending,
        );
        final account = _account(openingBalanceMinor: -100000);
        final before = calculator.calculate(
          account: account,
          transactions: [futurePurchase],
          currentBalanceMinor: -150000,
          today: DateTime(2026, 8, 19),
        );
        final onDate = calculator.calculate(
          account: account,
          transactions: [futurePurchase],
          currentBalanceMinor: -150000,
          today: DateTime(2026, 8, 20),
        );

        expect(before.estimatedInterestMinor, 3100);
        expect(before.projectedStatementMinor, -103100);
        expect(onDate.estimatedInterestMinor, 3700);
        expect(onDate.projectedStatementMinor, -153700);
      },
    );

    test('zero APR projects no interest', () {
      final estimate = calculator.calculate(
        account: _account(
          openingBalanceMinor: -100000,
          annualPercentageRate: 0,
        ),
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 8, 10),
      );

      expect(estimate.estimatedInterestMinor, 0);
      expect(estimate.projectedStatementMinor, -100000);
    });

    test('zero current balance with no earlier debt stays zero', () {
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: 0),
        transactions: const [],
        currentBalanceMinor: 0,
        today: DateTime(2026, 8, 10),
      );

      expect(estimate.averageDailyBalanceMinor, 0);
      expect(estimate.estimatedInterestMinor, 0);
      expect(estimate.projectedStatementMinor, 0);
    });

    test('positive card balance is not treated as interest-bearing debt', () {
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: 25000),
        transactions: const [],
        currentBalanceMinor: 25000,
        today: DateTime(2026, 8, 10),
      );

      expect(estimate.averageDailyBalanceMinor, 0);
      expect(estimate.estimatedInterestMinor, 0);
      expect(estimate.projectedStatementMinor, 25000);
    });

    test('outbound transfer from card increases projected debt', () {
      final transfer = _transaction(
        id: 'card-transfer',
        type: TransactionType.transfer,
        date: DateTime(2026, 8, 16),
        amountMinor: 30000,
        accountId: 'card',
        transferAccountId: 'wallet',
      );
      final estimate = calculator.calculate(
        account: _account(openingBalanceMinor: -100000),
        transactions: [transfer],
        currentBalanceMinor: -130000,
        today: DateTime(2026, 8, 16),
      );

      expect(estimate.estimatedInterestMinor, 3580);
      expect(estimate.projectedStatementMinor, -133580);
    });

    test('payment due date behavior remains unchanged', () {
      expect(
        calculator.nextPaymentDueDate(
          paymentDueDay: 31,
          today: DateTime(2026, 2, 1),
        ),
        DateTime(2026, 2, 28),
      );
      expect(
        calculator.nextPaymentDueDate(
          paymentDueDay: 8,
          today: DateTime(2026, 8, 8),
        ),
        DateTime(2026, 8, 8),
      );
    });
  });
}

AccountRecord _account({
  required int openingBalanceMinor,
  DateTime? createdAt,
  int statementClosingDay = 31,
  double annualPercentageRate = 36.5,
}) {
  return AccountRecord(
    id: 'card',
    name: 'Card',
    type: AccountType.creditCard,
    openingBalanceMinor: openingBalanceMinor,
    interestEstimationEnabled: true,
    annualPercentageRate: annualPercentageRate,
    statementClosingDay: statementClosingDay,
    paymentDueDay: 8,
    sync: SyncMetadata.fresh(now: createdAt ?? DateTime(2026, 7, 1)),
  );
}

TransactionRecord _transaction({
  required String id,
  required TransactionType type,
  required DateTime date,
  required int amountMinor,
  String accountId = 'card',
  String? transferAccountId,
  TransactionStatus status = TransactionStatus.cleared,
}) {
  return TransactionRecord(
    id: id,
    type: type,
    accountId: accountId,
    transferAccountId: transferAccountId,
    date: date,
    payee: id,
    amountMinor: amountMinor,
    status: status,
    sync: SyncMetadata.fresh(now: date),
  );
}

TransactionRecord _payment({
  required String id,
  required DateTime date,
  required int amountMinor,
}) {
  return _transaction(
    id: id,
    type: TransactionType.transfer,
    accountId: 'checking',
    transferAccountId: 'card',
    date: date,
    amountMinor: amountMinor,
  );
}
