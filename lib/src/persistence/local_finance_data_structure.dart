/// Validate the local storage envelope before permissive domain decoding.
/// This is not the backup validator: older local records may omit later
/// collections/fields, and their existing domain defaults remain authoritative.
/// Present malformed collections must never be interpreted as empty ones.
void validateLocalFinanceDataStructure(Map<String, Object?> root) {
  const core = [
    'accounts',
    'categories',
    'transactions',
    'scheduledTransactions',
    'budgets',
  ];
  const later = [
    'goals',
    'funds',
    'reservationOperations',
    'goalContributions',
    'goalFundingEvents',
  ];
  List<Map> objects(Object? value, String path) {
    if (value is! List || value.any((item) => item is! Map)) {
      throw FormatException('Invalid local collection: $path');
    }
    return value.cast<Map>();
  }

  for (final key in [...core, ...later]) {
    if (!root.containsKey(key) && later.contains(key)) continue;
    for (final record in objects(root[key], key)) {
      final id = record['id'];
      if (id is! String || id.trim().isEmpty || record['sync'] is! Map) {
        throw FormatException('Incomplete local record in $key');
      }
      final nestedLists = switch (key) {
        'transactions' => ['splitLines'],
        'scheduledTransactions' => [
          'splitLines',
          'goalFundingAllocations',
          'occurrences',
        ],
        'budgets' => ['configurationRevisions'],
        'goalFundingEvents' => ['allocations'],
        _ => <String>[],
      };
      for (final field in nestedLists) {
        if (record.containsKey(field)) objects(record[field], '$key.$field');
      }
      if (key == 'scheduledTransactions' &&
          record.containsKey('occurrenceStates')) {
        final states = record['occurrenceStates'];
        if (states is! Map || states.values.any((value) => value is! Map)) {
          throw const FormatException('Invalid local occurrence states');
        }
      }
    }
  }
  if (root['preferences'] is! Map) {
    throw const FormatException('Invalid local preferences');
  }
}
