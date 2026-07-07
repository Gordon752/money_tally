import 'package:flutter/widgets.dart';

import 'finance_data_store.dart';

class FinanceDataStoreScope extends InheritedNotifier<FinanceDataStore> {
  const FinanceDataStoreScope({
    required FinanceDataStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static FinanceDataStore watch(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<FinanceDataStoreScope>();
    assert(scope != null, 'No FinanceDataStoreScope found');
    return scope!.notifier!;
  }

  static FinanceDataStore read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<FinanceDataStoreScope>();
    final scope = element?.widget as FinanceDataStoreScope?;
    assert(scope != null, 'No FinanceDataStoreScope found');
    return scope!.notifier!;
  }
}
