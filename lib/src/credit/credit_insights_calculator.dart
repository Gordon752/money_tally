/// A deliberately simple, transparent first-pass Credit Insights estimate.
///
/// The estimator uses the current revolving balance and a 365-day simple
/// interest approximation. It is isolated from UI and transaction code so a
/// future average-daily-balance implementation can replace only this layer.
class CreditInsightsEstimate {
  const CreditInsightsEstimate({
    required this.nextStatementClosingDate,
    required this.daysUntilStatementClosing,
    required this.estimatedInterestMinor,
    required this.projectedStatementMinor,
  });

  final DateTime? nextStatementClosingDate;
  final int? daysUntilStatementClosing;

  /// A positive cost in minor units. Null means the inputs are incomplete.
  final int? estimatedInterestMinor;

  /// Uses the app's signed card-balance convention: a revolving balance and
  /// its projected statement are negative.
  final int? projectedStatementMinor;

  bool get hasInterestEstimate => estimatedInterestMinor != null;
}

class CreditInsightsCalculator {
  const CreditInsightsCalculator();

  CreditInsightsEstimate calculate({
    required int currentBalanceMinor,
    required double? annualPercentageRate,
    required int? statementClosingDay,
    DateTime? today,
  }) {
    final referenceDate = _calendarDate(today ?? DateTime.now());
    final closingDate = nextStatementClosingDate(
      statementClosingDay: statementClosingDay,
      today: referenceDate,
    );
    final daysUntilClosing = closingDate?.difference(referenceDate).inDays;

    if (annualPercentageRate == null ||
        annualPercentageRate.isNegative ||
        closingDate == null ||
        daysUntilClosing == null) {
      return CreditInsightsEstimate(
        nextStatementClosingDate: closingDate,
        daysUntilStatementClosing: daysUntilClosing,
        estimatedInterestMinor: null,
        projectedStatementMinor: null,
      );
    }

    // A zero or positive card balance has no revolving balance to estimate.
    if (currentBalanceMinor >= 0) {
      return CreditInsightsEstimate(
        nextStatementClosingDate: closingDate,
        daysUntilStatementClosing: daysUntilClosing,
        estimatedInterestMinor: 0,
        projectedStatementMinor: currentBalanceMinor,
      );
    }

    final simpleInterestMinor =
        (currentBalanceMinor.abs() *
                (annualPercentageRate / 100) *
                (daysUntilClosing / 365))
            .round();
    return CreditInsightsEstimate(
      nextStatementClosingDate: closingDate,
      daysUntilStatementClosing: daysUntilClosing,
      estimatedInterestMinor: simpleInterestMinor,
      projectedStatementMinor: currentBalanceMinor - simpleInterestMinor,
    );
  }

  /// Returns the next closing date, using a month's final day when a card is
  /// configured with a day that month does not contain (for example, Feb 31).
  DateTime? nextStatementClosingDate({
    required int? statementClosingDay,
    required DateTime today,
  }) {
    if (statementClosingDay == null ||
        statementClosingDay < 1 ||
        statementClosingDay > 31) {
      return null;
    }
    final referenceDate = _calendarDate(today);
    var closingDate = _closingDateFor(
      referenceDate.year,
      referenceDate.month,
      statementClosingDay,
    );
    if (closingDate.isBefore(referenceDate)) {
      closingDate = _closingDateFor(
        referenceDate.year,
        referenceDate.month + 1,
        statementClosingDay,
      );
    }
    return closingDate;
  }

  DateTime _closingDateFor(int year, int month, int day) {
    final finalDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > finalDay ? finalDay : day);
  }

  DateTime _calendarDate(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
