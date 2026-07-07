import 'dart:convert';

import '../domain/finance_data_set.dart';

class BackupCodec {
  const BackupCodec();

  String encodeJson(FinanceDataSet dataSet) {
    return const JsonEncoder.withIndent('  ').convert(dataSet.toJson());
  }

  FinanceDataSet decodeJson(String rawJson) {
    final decoded = jsonDecode(rawJson) as Map<String, Object?>;
    return FinanceDataSet.fromJson(decoded);
  }
}
