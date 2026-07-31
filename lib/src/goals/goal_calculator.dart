import '../domain/goal.dart';
import '../domain/goal_funding.dart';

enum GoalProgressStatus {
  ahead,
  onTrack,
  behind,
  seriouslyBehind,
  noTargetDate,
  completed,
  aboveReserveTarget,
  fullyFunded,
  slightlyBelowTarget,
  replenishing,
  needsAttention,
  restoreOverdue,
  noRestoreDate,
  archived,
}

extension GoalProgressStatusLabel on GoalProgressStatus {
  String get label {
    return switch (this) {
      GoalProgressStatus.ahead => 'Ahead',
      GoalProgressStatus.onTrack => 'On track',
      GoalProgressStatus.behind => 'Behind',
      GoalProgressStatus.seriouslyBehind => 'Behind',
      GoalProgressStatus.noTargetDate => 'No deadline',
      GoalProgressStatus.completed => 'Completed',
      GoalProgressStatus.aboveReserveTarget => 'Above reserve target',
      GoalProgressStatus.fullyFunded => 'Fully funded',
      GoalProgressStatus.slightlyBelowTarget => 'Slightly below target',
      GoalProgressStatus.replenishing => 'Replenishing',
      GoalProgressStatus.needsAttention => 'Needs attention',
      GoalProgressStatus.restoreOverdue => 'Restore overdue',
      GoalProgressStatus.noRestoreDate => 'No restore-by date',
      GoalProgressStatus.archived => 'Archived',
    };
  }
}

class GoalProgressMetrics {
  const GoalProgressMetrics({
    required this.currentAmountMinor,
    required this.remainingAmountMinor,
    required this.percentageComplete,
    required this.expectedAmountMinor,
    required this.aheadBehindMinor,
    required this.requiredWeeklyMinor,
    required this.requiredMonthlyMinor,
    required this.status,
    this.projectedCompletionDate,
  });

  final int currentAmountMinor;
  final int remainingAmountMinor;
  final double percentageComplete;
  final int expectedAmountMinor;
  final int aheadBehindMinor;
  final int requiredWeeklyMinor;
  final int requiredMonthlyMinor;
  final DateTime? projectedCompletionDate;
  final GoalProgressStatus status;
}

class GoalCalculator {
  const GoalCalculator();

  static const onTrackFloor = 0.95;
  static const moderatelyBehindFloor = 0.75;
  static const aheadTolerance = 1.05;
  static const reserveSlightlyBelowFloor = 0.95;
  static const reserveNeedsAttentionFloor = 0.75;
  static const reserveAboveTolerance = 1.05;
  static const averageDaysPerMonth = 30.4375;

  int currentAmountMinor(
    GoalRecord goal,
    Iterable<GoalContributionRecord> contributions,
    Iterable<GoalFundingEventRecord> fundingEvents,
  ) {
    final progressEntries = contributions
        .where(
          (contribution) =>
              contribution.goalId == goal.id && contribution.isActive,
        )
        .fold<int>(
          0,
          (total, contribution) => total + contribution.amountMinor.abs(),
        );
    final fundingAllocations = fundingEvents
        .where((event) => event.isActive)
        .expand((event) => event.allocations)
        .where((allocation) => allocation.goalId == goal.id)
        .fold<int>(
          0,
          (total, allocation) => total + allocation.amountMinor.abs(),
        );
    return goal.startingAmountMinor + progressEntries + fundingAllocations;
  }

  GoalProgressMetrics calculate(
    GoalRecord goal,
    Iterable<GoalContributionRecord> contributions, {
    Iterable<GoalFundingEventRecord> fundingEvents = const [],
    int? currentAmountMinorOverride,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final today = _dateOnly(anchor);
    final current =
        currentAmountMinorOverride ??
        currentAmountMinor(goal, contributions, fundingEvents);
    final target = goal.targetAmountMinor.abs();
    final remaining = (target - current).clamp(0, target).toInt();
    final percentage = target == 0 ? 0.0 : current / target;

    if (goal.status == GoalStatus.archived) {
      return GoalProgressMetrics(
        currentAmountMinor: current,
        remainingAmountMinor: remaining,
        percentageComplete: percentage,
        expectedAmountMinor: current,
        aheadBehindMinor: 0,
        requiredWeeklyMinor: 0,
        requiredMonthlyMinor: 0,
        status: GoalProgressStatus.archived,
      );
    }
    if (goal.status == GoalStatus.completed) {
      return GoalProgressMetrics(
        currentAmountMinor: current,
        remainingAmountMinor: 0,
        percentageComplete: percentage,
        expectedAmountMinor: target,
        aheadBehindMinor: current - target,
        requiredWeeklyMinor: 0,
        requiredMonthlyMinor: 0,
        status: GoalProgressStatus.completed,
      );
    }
    if (goal.goalType == GoalType.maintainBalance) {
      return _calculateMaintainBalance(
        goal: goal,
        current: current,
        target: target,
        percentage: percentage,
        remaining: remaining,
        today: today,
      );
    }
    if (current >= target) {
      return GoalProgressMetrics(
        currentAmountMinor: current,
        remainingAmountMinor: 0,
        percentageComplete: percentage,
        expectedAmountMinor: target,
        aheadBehindMinor: current - target,
        requiredWeeklyMinor: 0,
        requiredMonthlyMinor: 0,
        status: GoalProgressStatus.completed,
      );
    }
    final targetDate = goal.targetDate == null
        ? null
        : _dateOnly(goal.targetDate!);
    if (targetDate == null) {
      return GoalProgressMetrics(
        currentAmountMinor: current,
        remainingAmountMinor: remaining,
        percentageComplete: percentage,
        expectedAmountMinor: goal.startingAmountMinor,
        aheadBehindMinor: current - goal.startingAmountMinor,
        requiredWeeklyMinor: 0,
        requiredMonthlyMinor: 0,
        status: GoalProgressStatus.noTargetDate,
      );
    }

    final start = _dateOnly(goal.createdDate);
    final totalDays = targetDate.difference(start).inDays;
    final elapsedDays = totalDays <= 0
        ? 0
        : today.difference(start).inDays.clamp(0, totalDays);
    final plannedGrowth = (target - goal.startingAmountMinor).clamp(0, target);
    final expected = totalDays <= 0
        ? target
        : goal.startingAmountMinor +
              (plannedGrowth * elapsedDays / totalDays).round();
    final aheadBehind = current - expected;
    final daysRemaining = targetDate.difference(today).inDays;
    final weekly = daysRemaining <= 0
        ? remaining
        : (remaining * 7 / daysRemaining).ceil();
    final monthly = daysRemaining <= 0
        ? remaining
        : (remaining * averageDaysPerMonth / daysRemaining).ceil();
    final expectedProgress = expected <= 0 ? 1.0 : current / expected;
    final status = targetDate.isBefore(today)
        ? GoalProgressStatus.seriouslyBehind
        : expectedProgress >= aheadTolerance
        ? GoalProgressStatus.ahead
        : expectedProgress >= onTrackFloor
        ? GoalProgressStatus.onTrack
        : expectedProgress >= moderatelyBehindFloor
        ? GoalProgressStatus.behind
        : GoalProgressStatus.seriouslyBehind;

    return GoalProgressMetrics(
      currentAmountMinor: current,
      remainingAmountMinor: remaining,
      percentageComplete: percentage,
      expectedAmountMinor: expected,
      aheadBehindMinor: aheadBehind,
      requiredWeeklyMinor: weekly,
      requiredMonthlyMinor: monthly,
      projectedCompletionDate: _projectedCompletionDate(
        goal,
        contributions,
        current,
        remaining,
        today,
      ),
      status: status,
    );
  }

  GoalProgressMetrics _calculateMaintainBalance({
    required GoalRecord goal,
    required int current,
    required int target,
    required double percentage,
    required int remaining,
    required DateTime today,
  }) {
    if (current >= target) {
      return GoalProgressMetrics(
        currentAmountMinor: current,
        remainingAmountMinor: 0,
        percentageComplete: percentage,
        expectedAmountMinor: target,
        aheadBehindMinor: current - target,
        requiredWeeklyMinor: 0,
        requiredMonthlyMinor: 0,
        status: percentage >= reserveAboveTolerance
            ? GoalProgressStatus.aboveReserveTarget
            : GoalProgressStatus.fullyFunded,
      );
    }

    final restoreDate = goal.targetDate == null
        ? null
        : _dateOnly(goal.targetDate!);
    if (restoreDate == null) {
      return GoalProgressMetrics(
        currentAmountMinor: current,
        remainingAmountMinor: remaining,
        percentageComplete: percentage,
        expectedAmountMinor: target,
        aheadBehindMinor: current - target,
        requiredWeeklyMinor: 0,
        requiredMonthlyMinor: 0,
        status: GoalProgressStatus.noRestoreDate,
      );
    }

    final daysRemaining = restoreDate.difference(today).inDays;
    final weekly = daysRemaining <= 0
        ? remaining
        : (remaining * 7 / daysRemaining).ceil();
    final monthly = daysRemaining <= 0
        ? remaining
        : (remaining * averageDaysPerMonth / daysRemaining).ceil();
    final status = restoreDate.isBefore(today)
        ? GoalProgressStatus.restoreOverdue
        : percentage >= reserveSlightlyBelowFloor
        ? GoalProgressStatus.slightlyBelowTarget
        : percentage >= reserveNeedsAttentionFloor
        ? GoalProgressStatus.replenishing
        : GoalProgressStatus.needsAttention;

    return GoalProgressMetrics(
      currentAmountMinor: current,
      remainingAmountMinor: remaining,
      percentageComplete: percentage,
      expectedAmountMinor: target,
      aheadBehindMinor: current - target,
      requiredWeeklyMinor: weekly,
      requiredMonthlyMinor: monthly,
      status: status,
    );
  }

  DateTime? _projectedCompletionDate(
    GoalRecord goal,
    Iterable<GoalContributionRecord> contributions,
    int current,
    int remaining,
    DateTime today,
  ) {
    if (remaining <= 0) return today;
    final start = _dateOnly(goal.createdDate);
    final elapsedDays = today.difference(start).inDays;
    if (elapsedDays <= 0) return null;
    final contributed = current - goal.startingAmountMinor;
    if (contributed <= 0) return null;
    final dailyRate = contributed / elapsedDays;
    if (dailyRate <= 0) return null;
    return today.add(Duration(days: (remaining / dailyRate).ceil()));
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
