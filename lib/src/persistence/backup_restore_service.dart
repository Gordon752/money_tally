import 'dart:convert';

import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/goal.dart';
import '../domain/scheduled_transaction.dart';
import '../domain/transaction.dart';
import '../domain/user_preferences.dart';

const currentBackupSchemaVersion = 4;
const supportedBackupSchemaVersions = {2, currentBackupSchemaVersion};

class BackupValidationException implements Exception {
  const BackupValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ValidatedBackup {
  const ValidatedBackup({
    required this.dataSet,
    required this.sourceSchemaVersion,
    required this.schemaVersion,
    required this.originalJson,
    this.exportedAt,
  });

  final FinanceDataSet dataSet;
  final int sourceSchemaVersion;
  final int schemaVersion;
  final String originalJson;
  final DateTime? exportedAt;
}

/// Strict boundary used only for user-selected backup files.
///
/// Normal local/cloud decoding remains backward compatible. A destructive
/// restore is intentionally stricter: required collections, enum values,
/// stable IDs, and cross-record references must all be trustworthy before the
/// current data set can be replaced.
class BackupRestoreValidator {
  const BackupRestoreValidator();

  ValidatedBackup validate(String rawJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException {
      throw const BackupValidationException(
        'This file is not valid JSON and cannot be restored safely.',
      );
    }
    if (decoded is! Map) {
      throw const BackupValidationException(
        'This file is not a recognizable Trackmark backup.',
      );
    }
    final root = decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final sourceVersion = root['schemaVersion'];
    if (sourceVersion is! int) {
      throw const BackupValidationException(
        'This backup does not contain a valid schema version.',
      );
    }
    if (sourceVersion > currentBackupSchemaVersion) {
      throw BackupValidationException(
        'This backup was created by a newer version of Trackmark '
        '(schema $sourceVersion). Update Trackmark before restoring it.',
      );
    }
    if (!supportedBackupSchemaVersions.contains(sourceVersion)) {
      throw BackupValidationException(
        'Trackmark cannot safely migrate backup schema $sourceVersion.',
      );
    }

    _validateRequiredStructure(root, sourceVersion);
    final migrated = _migrateToCurrent(root, sourceVersion);
    _validateEnumValues(migrated);

    final FinanceDataSet dataSet;
    try {
      dataSet = FinanceDataSet.fromJson(migrated);
    } on Object {
      throw const BackupValidationException(
        'This backup contains invalid or incomplete Trackmark records.',
      );
    }
    _validateDataSet(dataSet);

    DateTime? exportedAt;
    final exportedAtValue = root['exportedAt'];
    if (exportedAtValue != null) {
      if (exportedAtValue is! String) {
        throw const BackupValidationException(
          'The backup creation date is invalid.',
        );
      }
      exportedAt = DateTime.tryParse(exportedAtValue);
      if (exportedAt == null) {
        throw const BackupValidationException(
          'The backup creation date is invalid.',
        );
      }
    }

    return ValidatedBackup(
      dataSet: dataSet,
      sourceSchemaVersion: sourceVersion,
      schemaVersion: currentBackupSchemaVersion,
      originalJson: rawJson,
      exportedAt: exportedAt,
    );
  }

  void _validateRequiredStructure(Map<String, Object?> root, int version) {
    const commonCollections = [
      'accounts',
      'categories',
      'transactions',
      'scheduledTransactions',
      'budgets',
    ];
    for (final key in commonCollections) {
      _requireRecordList(root, key);
    }
    if (version >= 4) {
      for (final key in const [
        'goals',
        'goalContributions',
        'goalFundingEvents',
      ]) {
        _requireRecordList(root, key);
      }
    }
    if (root['preferences'] is! Map) {
      throw const BackupValidationException(
        'The backup is missing Trackmark preferences.',
      );
    }
  }

  void _requireRecordList(Map<String, Object?> root, String key) {
    final value = root[key];
    if (value is! List || value.any((item) => item is! Map)) {
      throw BackupValidationException(
        'The backup is missing a valid $key collection.',
      );
    }
    for (final item in value.cast<Map>()) {
      final id = item['id'];
      if (id is! String || id.trim().isEmpty || item['sync'] is! Map) {
        throw BackupValidationException(
          'The $key collection contains an incomplete record.',
        );
      }
    }
  }

  Map<String, Object?> _migrateToCurrent(
    Map<String, Object?> root,
    int sourceVersion,
  ) {
    if (sourceVersion == currentBackupSchemaVersion) return root;
    if (sourceVersion == 2) {
      return {
        ...root,
        'schemaVersion': currentBackupSchemaVersion,
        'goals': const <Object?>[],
        'goalContributions': const <Object?>[],
        'goalFundingEvents': const <Object?>[],
      };
    }
    throw BackupValidationException(
      'Trackmark cannot safely migrate backup schema $sourceVersion.',
    );
  }

  void _validateEnumValues(Map<String, Object?> root) {
    _validateEnums(root, 'accounts', 'type', AccountType.values);
    _validateEnums(root, 'categories', 'kind', CategoryKind.values);
    _validateEnums(root, 'transactions', 'type', TransactionType.values);
    _validateEnums(
      root,
      'transactions',
      'status',
      TransactionStatus.values,
      optional: true,
    );
    _validateEnums(
      root,
      'scheduledTransactions',
      'type',
      TransactionType.values,
    );
    _validateEnums(
      root,
      'scheduledTransactions',
      'frequency',
      RecurrenceFrequency.values,
    );
    _validateEnums(
      root,
      'scheduledTransactions',
      'alertPreference',
      AlertPreference.values,
      optional: true,
    );
    _validateEnums(
      root,
      'scheduledTransactions',
      'lastAction',
      ScheduledAction.values,
      optional: true,
    );
    _validateEnums(root, 'budgets', 'period', BudgetPeriod.values);
    _validateEnums(root, 'goals', 'status', GoalStatus.values);
    _validateEnums(root, 'goals', 'goalType', GoalType.values, optional: true);

    final preferences = _stringMap(root['preferences']);
    _validateEnum(
      preferences,
      'launchScreen',
      LaunchScreen.values,
      optional: true,
    );
    _validateEnum(
      preferences,
      'preferredPlanSegment',
      PlanSegment.values,
      optional: true,
    );
    _validateEnum(
      preferences,
      'appearanceMode',
      AppearanceMode.values,
      optional: true,
    );
    _validateEnum(
      preferences,
      'floatingAddButtonPosition',
      FloatingAddButtonPosition.values,
      optional: true,
    );
    _validateEnum(
      preferences,
      'defaultTransactionType',
      DefaultTransactionType.values,
      optional: true,
    );
    _validateEnum(
      preferences,
      'lastUsedTransactionType',
      TransactionType.values,
      optional: true,
    );
    _validateEnum(
      preferences,
      'defaultTransactionAccountMode',
      AccountDefaultMode.values,
      optional: true,
    );
    _validateEnum(
      preferences,
      'defaultTransferSourceMode',
      AccountDefaultMode.values,
      optional: true,
    );

    for (final rawSchedule in _recordMaps(root, 'scheduledTransactions')) {
      for (final occurrence in _mapList(rawSchedule['occurrences'])) {
        _validateEnum(occurrence, 'status', ScheduledOccurrenceStatus.values);
      }
    }
    for (final rawBudget in _recordMaps(root, 'budgets')) {
      for (final revision in _mapList(rawBudget['configurationRevisions'])) {
        _validateEnum(revision, 'period', BudgetPeriod.values);
      }
    }
    for (final rawGoal in _recordMaps(root, 'goals')) {
      final method = rawGoal['fundingMethod'];
      if (method != null &&
          method != 'reserveFromAccount' &&
          method != 'accountFunded' &&
          method != 'trackingOnly') {
        throw const BackupValidationException(
          'The backup contains an unsupported Goal funding method.',
        );
      }
    }
  }

  void _validateEnums<T extends Enum>(
    Map<String, Object?> root,
    String collection,
    String key,
    List<T> values, {
    bool optional = false,
  }) {
    for (final item in _recordMaps(root, collection)) {
      _validateEnum(item, key, values, optional: optional);
    }
  }

  void _validateEnum<T extends Enum>(
    Map<String, Object?> item,
    String key,
    List<T> values, {
    bool optional = false,
  }) {
    final value = item[key];
    if (value == null && optional) return;
    if (value is! String || !values.any((item) => item.name == value)) {
      throw BackupValidationException(
        'The backup contains an unsupported $key value.',
      );
    }
  }

  void _validateDataSet(FinanceDataSet dataSet) {
    _requireUniqueIds('accounts', dataSet.accounts.map((item) => item.id));
    _requireUniqueIds('categories', dataSet.categories.map((item) => item.id));
    _requireUniqueIds(
      'transactions',
      dataSet.transactions.map((item) => item.id),
    );
    _requireUniqueIds(
      'scheduled transactions',
      dataSet.scheduledTransactions.map((item) => item.id),
    );
    _requireUniqueIds('budgets', dataSet.budgets.map((item) => item.id));
    _requireUniqueIds('goals', dataSet.goals.map((item) => item.id));
    _requireUniqueIds(
      'Goal contributions',
      dataSet.goalContributions.map((item) => item.id),
    );
    _requireUniqueIds(
      'Goal funding events',
      dataSet.goalFundingEvents.map((item) => item.id),
    );

    final accounts = {for (final item in dataSet.accounts) item.id: item};
    final categories = {for (final item in dataSet.categories) item.id: item};
    final transactions = {
      for (final item in dataSet.transactions) item.id: item,
    };
    final schedules = {
      for (final item in dataSet.scheduledTransactions) item.id: item,
    };
    final goals = {for (final item in dataSet.goals) item.id: item};
    final fundingEvents = {
      for (final item in dataSet.goalFundingEvents) item.id: item,
    };

    for (final account in dataSet.accounts) {
      if (account.creditLimitMinor != null && account.creditLimitMinor! < 0) {
        throw const BackupValidationException(
          'A credit limit in this backup is invalid.',
        );
      }
      if ((account.annualPercentageRate ?? 0) < 0 ||
          !_validDay(account.statementClosingDay) ||
          !_validDay(account.paymentDueDay)) {
        throw BackupValidationException(
          'Credit Insights settings for ${account.name} are invalid.',
        );
      }
      final goalId = account.goalId;
      if (goalId != null &&
          goalId.isNotEmpty &&
          !account.isDetachedGoalAccount &&
          !goals.containsKey(goalId)) {
        throw const BackupValidationException(
          'A hidden Goal account references a missing Goal.',
        );
      }
    }

    for (final category in dataSet.categories) {
      final parentId = category.parentCategoryId;
      if (parentId != null &&
          (parentId == category.id || !categories.containsKey(parentId))) {
        throw const BackupValidationException(
          'A subcategory references a missing or invalid parent category.',
        );
      }
    }

    for (final transaction in dataSet.transactions) {
      _requireAccount(accounts, transaction.accountId, 'transaction');
      if (transaction.type == TransactionType.transfer) {
        final destination = transaction.transferAccountId;
        if (destination == null || destination == transaction.accountId) {
          throw const BackupValidationException(
            'A transfer has an invalid destination account.',
          );
        }
        _requireAccount(accounts, destination, 'transfer');
      } else if (transaction.transferAccountId != null) {
        throw const BackupValidationException(
          'A non-transfer transaction contains a transfer destination.',
        );
      }
      _validateCategoryReferences(
        transaction.categoryId,
        transaction.splitLines,
        categories,
      );
      if (!transaction.hasValidSplitTotal) {
        throw const BackupValidationException(
          'A transaction contains unbalanced split allocations.',
        );
      }
      final scheduleId = transaction.scheduledTransactionId;
      if (scheduleId != null && !schedules.containsKey(scheduleId)) {
        throw const BackupValidationException(
          'A transaction references a missing scheduled transaction.',
        );
      }
      final eventId = transaction.goalFundingEventId;
      if (eventId != null && !fundingEvents.containsKey(eventId)) {
        throw const BackupValidationException(
          'A transaction references a missing Goal funding event.',
        );
      }
    }

    for (final schedule in dataSet.scheduledTransactions) {
      _requireAccount(accounts, schedule.accountId, 'scheduled transaction');
      if (schedule.type == TransactionType.transfer) {
        final destination = schedule.transferAccountId;
        if (destination == null || destination == schedule.accountId) {
          throw const BackupValidationException(
            'A scheduled transfer has an invalid destination account.',
          );
        }
        _requireAccount(accounts, destination, 'scheduled transfer');
      }
      _validateCategoryReferences(
        schedule.categoryId,
        schedule.splitLines,
        categories,
      );
      if (!schedule.hasValidSplitTotal ||
          !schedule.hasValidGoalFundingAllocations) {
        throw const BackupValidationException(
          'A scheduled transaction contains invalid allocations.',
        );
      }
      if (schedule.goalId case final goalId?) {
        if (!goals.containsKey(goalId)) {
          throw const BackupValidationException(
            'A scheduled transaction references a missing Goal.',
          );
        }
      }
      for (final allocation in schedule.goalFundingAllocations) {
        if (!goals.containsKey(allocation.goalId)) {
          throw const BackupValidationException(
            'Scheduled Goal funding references a missing Goal.',
          );
        }
      }
      final occurrenceIds = <String>{};
      for (final occurrence in schedule.occurrences) {
        final occurrenceKey = occurrence.scheduledDate.toIso8601String();
        if (!occurrenceIds.add(occurrenceKey)) {
          throw const BackupValidationException(
            'A scheduled transaction contains duplicate occurrences.',
          );
        }
        if (occurrence.transactionId case final transactionId?) {
          if (!transactions.containsKey(transactionId)) {
            throw const BackupValidationException(
              'A scheduled occurrence references a missing transaction.',
            );
          }
        }
        if (occurrence.goalFundingEventId case final eventId?) {
          if (!fundingEvents.containsKey(eventId)) {
            throw const BackupValidationException(
              'A scheduled occurrence references a missing Goal funding event.',
            );
          }
        }
      }
    }

    for (final budget in dataSet.budgets) {
      for (final categoryId in budget.categoryIds) {
        _requireCategory(categories, categoryId, 'Budget');
      }
      for (final revision in budget.configurationRevisions) {
        for (final categoryId in revision.categoryIds) {
          _requireCategory(categories, categoryId, 'Budget revision');
        }
      }
    }

    for (final goal in dataSet.goals) {
      if (goal.accountId case final accountId?) {
        final account = accounts[accountId];
        if (account == null || account.goalId != goal.id) {
          throw const BackupValidationException(
            'A Goal is not linked to its expected hidden account.',
          );
        }
      }
      if (goal.defaultFundingAccountId case final accountId?) {
        _requireAccount(accounts, accountId, 'Goal');
      }
    }
    for (final contribution in dataSet.goalContributions) {
      if (!goals.containsKey(contribution.goalId)) {
        throw const BackupValidationException(
          'A Goal contribution references a missing Goal.',
        );
      }
      if (contribution.sourceAccountId case final accountId?) {
        _requireAccount(accounts, accountId, 'Goal contribution');
      }
    }
    for (final event in dataSet.goalFundingEvents) {
      _requireAccount(accounts, event.sourceAccountId, 'Goal funding event');
      final allocationIds = <String>{};
      var total = 0;
      for (final allocation in event.allocations) {
        if (!allocationIds.add(allocation.id) ||
            allocation.fundingEventId != event.id ||
            !goals.containsKey(allocation.goalId) ||
            allocation.amountMinor <= 0) {
          throw const BackupValidationException(
            'A Goal funding event contains invalid allocations.',
          );
        }
        total += allocation.amountMinor;
      }
      if (total != event.totalAmountMinor.abs()) {
        throw const BackupValidationException(
          'A Goal funding event contains unbalanced allocations.',
        );
      }
      if (event.scheduledTransactionId case final scheduleId?) {
        if (!schedules.containsKey(scheduleId)) {
          throw const BackupValidationException(
            'A Goal funding event references a missing schedule.',
          );
        }
      }
    }
  }

  bool _validDay(int? value) => value == null || (value >= 1 && value <= 31);

  void _validateCategoryReferences(
    String? categoryId,
    List<TransactionSplitLine> splitLines,
    Map<String, CategoryRecord> categories,
  ) {
    if (categoryId != null) {
      _requireCategory(categories, categoryId, 'Transaction');
    }
    final ids = <String>{};
    for (final line in splitLines) {
      if (line.id.trim().isEmpty || !ids.add(line.id)) {
        throw const BackupValidationException(
          'A transaction contains an invalid split allocation.',
        );
      }
      _requireCategory(categories, line.categoryId, 'Split allocation');
    }
  }

  void _requireAccount(
    Map<String, AccountRecord> accounts,
    String id,
    String owner,
  ) {
    if (!accounts.containsKey(id)) {
      throw BackupValidationException('$owner references a missing account.');
    }
  }

  void _requireCategory(
    Map<String, CategoryRecord> categories,
    String id,
    String owner,
  ) {
    if (!categories.containsKey(id)) {
      throw BackupValidationException('$owner references a missing category.');
    }
  }

  void _requireUniqueIds(String label, Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (id.trim().isEmpty || !seen.add(id)) {
        throw BackupValidationException(
          'The backup contains duplicate or empty IDs in $label.',
        );
      }
    }
  }

  List<Map<String, Object?>> _recordMaps(
    Map<String, Object?> root,
    String key,
  ) => _mapList(root[key]);

  List<Map<String, Object?>> _mapList(Object? value) =>
      (value as List<Object?>? ?? const [])
          .whereType<Map>()
          .map(_stringMap)
          .toList(growable: false);

  Map<String, Object?> _stringMap(Object? value) => (value as Map)
      .map<String, Object?>((key, item) => MapEntry(key.toString(), item));
}
