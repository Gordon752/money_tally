T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

DateTime dateTimeFromJson(Object? value, {DateTime? fallback}) {
  if (value is String) return DateTime.parse(value);
  return fallback ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

Map<String, Object?> stringMap(Object? value) {
  if (value is! Map<Object?, Object?>) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Map<String, Object?>> stringMapList(Object? value) {
  if (value is! List<Object?>) return const [];
  return value.map(stringMap).toList();
}
