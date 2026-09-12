import '../domain/account.dart';
import '../domain/transaction.dart';

enum CreditInsightsEstimateCompleteness {
  complete,
  partial,
  insufficientHistory,
}

/// A read-only estimate for the currently active credit-card billing cycle.
///
/// Money values remain in minor units. [averageDailyBalanceMinor] is a double
/// so the average is not rounded before interest is calculated.
class CreditInsightsEstimate {
  const CreditInsightsEstimate({
    required this.nextStatementClosingDate,
    required this.daysUntilStatementClosing,
    required this.cycleStart,
    required this.cycleEnd,
    required this.representedStart,
    required this.representedEnd,
    required this.daysRepresented,
    required this.totalCycleDays,
    required this.averageDailyBalanceMinor,
    required this.estimatedInterestMinor,
    required this.projectedStatementMinor,
    required this.estimateCompleteness,
  });

  final DateTime? nextStatementClosingDate;
  final int? daysUntilStatementClosing;
  final DateTime? cycleStart;
  final DateTime? cycleEnd;
  final DateTime? representedStart;
  final DateTime? representedEnd;
  final int daysRepresented;
  final int totalCycleDays;
  final double? averageDailyBalanceMinor;

  /// A positive estimated cost in minor units. Null means calculation inputs
  /// or reliable account history are unavailable.
  final int? estimatedInterestMinor;

  /// Uses Trackmark's signed card-balance convention: debt and its projected
  /// statement are negative values.
  final int? projectedStatementMinor;
  final CreditInsightsEstimateCompleteness estimateCompleteness;

  bool get hasInterestEstimate => estimatedInterestMinor != null;
}

/// Reconstructs end-of-day credit-card debt from Trackmark's existing account
/// baseline and ordinary transaction effects.
///
/// The service never writes account data. It intentionally does not infer
/// issuer grace periods, posting rules, compounding, or multiple APR buckets.
class CreditInsightsCalculator {
  const CreditInsightsCalculator();

  CreditInsightsEstimate calculate({
    required AccountRecord account,
    required Iterable<TransactionRecord> transactions,
    required int currentBalanceMinor,
    DateTime? today,
  }) {
    final referenceDate = _calendarDate(today ?? DateTime.now());
    final cycle = currentStatementCycle(
      statementClosingDay: account.statementClosingDay,
      today: referenceDate,
    );
    final closingDate = cycle?.end;
    final daysUntilClosing = closingDate == null
        ? null
        : _calendarDayDifference(referenceDate, closingDate);
    final apr = account.annualPercentageRate;

    if (cycle == null || apr == null || apr.isNegative) {
      return _unavailableEstimate(
        closingDate: closingDate,
        daysUntilClosing: daysUntilClosing,
        cycle: cycle,
      );
    }

    final historyStart = _calendarDate(account.sync.createdAt);
    final representedStart = historyStart.isAfter(cycle.start)
        ? historyStart
        : cycle.start;
    final representedEnd = referenceDate.isBefore(cycle.end)
        ? referenceDate
        : cycle.end;
    final totalCycleDays = _inclusiveDays(cycle.start, cycle.end);

    if (representedStart.isAfter(representedEnd)) {
      return CreditInsightsEstimate(
        nextStatementClosingDate: closingDate,
        daysUntilStatementClosing: daysUntilClosing,
        cycleStart: cycle.start,
        cycleEnd: cycle.end,
        representedStart: null,
        representedEnd: null,
        daysRepresented: 0,
        totalCycleDays: totalCycleDays,
        averageDailyBalanceMinor: null,
        estimatedInterestMinor: null,
        projectedStatementMinor: null,
        estimateCompleteness:
            CreditInsightsEstimateCompleteness.insufficientHistory,
      );
    }

    final dailyDeltas = <DateTime, int>{};
    var futureDeltasMinor = 0;
    for (final transaction in transactions) {
      if (transaction.isDeleted) continue;
      final delta = transaction.deltaForAccount(account.id);
      if (delta == 0) continue;
      final date = _calendarDate(transaction.date);
      dailyDeltas[date] = (dailyDeltas[date] ?? 0) + delta;
      if (date.isAfter(referenceDate)) {
        futureDeltasMinor += delta;
      }
    }

    var signedBalanceMinor = account.openingBalanceMinor;
    for (final entry in dailyDeltas.entries) {
      if (entry.key.isBefore(representedStart)) {
        signedBalanceMinor += entry.value;
      }
    }

    var representedDay = representedStart;
    var daysRepresented = 0;
    var summedDailyDebtMinor = 0;
    while (!representedDay.isAfter(representedEnd)) {
      signedBalanceMinor += dailyDeltas[representedDay] ?? 0;
      // Credit-card debt is negative in Trackmark. A zero or positive balance
      // is not interest-bearing debt for this estimate.
      summedDailyDebtMinor += signedBalanceMinor < 0
          ? signedBalanceMinor.abs()
          : 0;
      daysRepresented += 1;
      representedDay = _nextCalendarDay(representedDay);
    }

    // The ordinary account balance includes every recorded transaction,
    // including future-dated records. Credit Insights must not let those
    // records affect the balance before their transaction date.
    final currentBalanceAsOfTodayMinor =
        currentBalanceMinor - futureDeltasMinor;
    final projectedDailyDebtMinor = currentBalanceAsOfTodayMinor < 0
        ? currentBalanceAsOfTodayMinor.abs()
        : 0;
    final remainingCycleDays = _calendarDayDifference(
      representedEnd,
      cycle.end,
    );
    final projectedSummedDailyDebtMinor =
        summedDailyDebtMinor + projectedDailyDebtMinor * remainingCycleDays;
    final projectedDaysRepresented = daysRepresented + remainingCycleDays;
    final averageDailyBalanceMinor =
        projectedSummedDailyDebtMinor / projectedDaysRepresented;
    final dailyPeriodicRate = apr / 100 / 365;
    final estimatedInterestMinor =
        (projectedSummedDailyDebtMinor * dailyPeriodicRate).round();

    return CreditInsightsEstimate(
      nextStatementClosingDate: closingDate,
      daysUntilStatementClosing: daysUntilClosing,
      cycleStart: cycle.start,
      cycleEnd: cycle.end,
      representedStart: representedStart,
      representedEnd: representedEnd,
      daysRepresented: daysRepresented,
      totalCycleDays: totalCycleDays,
      averageDailyBalanceMinor: averageDailyBalanceMinor,
      estimatedInterestMinor: estimatedInterestMinor,
      projectedStatementMinor:
          currentBalanceAsOfTodayMinor - estimatedInterestMinor,
      estimateCompleteness: historyStart.isAfter(cycle.start)
          ? CreditInsightsEstimateCompleteness.partial
          : CreditInsightsEstimateCompleteness.complete,
    );
  }

  CreditInsightsEstimate _unavailableEstimate({
    required DateTime? closingDate,
    required int? daysUntilClosing,
    required CreditStatementCycle? cycle,
  }) {
    return CreditInsightsEstimate(
      nextStatementClosingDate: closingDate,
      daysUntilStatementClosing: daysUntilClosing,
      cycleStart: cycle?.start,
      cycleEnd: cycle?.end,
      representedStart: null,
      representedEnd: null,
      daysRepresented: 0,
      totalCycleDays: cycle == null
          ? 0
          : _inclusiveDays(cycle.start, cycle.end),
      averageDailyBalanceMinor: null,
      estimatedInterestMinor: null,
      projectedStatementMinor: null,
      estimateCompleteness:
          CreditInsightsEstimateCompleteness.insufficientHistory,
    );
  }

  CreditStatementCycle? currentStatementCycle({
    required int? statementClosingDay,
    required DateTime today,
  }) {
    if (!_isValidConfiguredDay(statementClosingDay)) return null;
    final referenceDate = _calendarDate(today);
    final currentClose = _nextDayOfMonth(
      configuredDay: statementClosingDay,
      today: referenceDate,
    )!;
    final previousMonth = DateTime(
      currentClose.year,
      currentClose.month - 1,
      1,
    );
    final previousClose = _closingDateFor(
      previousMonth.year,
      previousMonth.month,
      statementClosingDay!,
    );
    return CreditStatementCycle(
      start: _nextCalendarDay(previousClose),
      end: currentClose,
    );
  }

  /// Returns the next closing date, using a month's final day when a card is
  /// configured with a day that month does not contain (for example, Feb 31).
  DateTime? nextStatementClosingDate({
    required int? statementClosingDay,
    required DateTime today,
  }) {
    return _nextDayOfMonth(configuredDay: statementClosingDay, today: today);
  }

  /// Returns the next payment due date, clamping configured days such as 31
  /// to the final valid day of shorter months.
  DateTime? nextPaymentDueDate({
    required int? paymentDueDay,
    required DateTime today,
  }) {
    return _nextDayOfMonth(configuredDay: paymentDueDay, today: today);
  }

  DateTime? _nextDayOfMonth({
    required int? configuredDay,
    required DateTime today,
  }) {
    if (!_isValidConfiguredDay(configuredDay)) return null;
    final referenceDate = _calendarDate(today);
    var date = _closingDateFor(
      referenceDate.year,
      referenceDate.month,
      configuredDay!,
    );
    if (date.isBefore(referenceDate)) {
      date = _closingDateFor(
        referenceDate.year,
        referenceDate.month + 1,
        configuredDay,
      );
    }
    return date;
  }

  bool _isValidConfiguredDay(int? day) => day != null && day >= 1 && day <= 31;

  int _inclusiveDays(DateTime start, DateTime end) =>
      _calendarDayDifference(start, end) + 1;

  int _calendarDayDifference(DateTime start, DateTime end) {
    final utcStart = DateTime.utc(start.year, start.month, start.day);
    final utcEnd = DateTime.utc(end.year, end.month, end.day);
    return utcEnd.difference(utcStart).inDays;
  }

  DateTime _nextCalendarDay(DateTime date) =>
      DateTime(date.year, date.month, date.day + 1);

  DateTime _closingDateFor(int year, int month, int day) {
    final finalDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > finalDay ? finalDay : day);
  }

  DateTime _calendarDate(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

class CreditStatementCycle {
  const CreditStatementCycle({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}
