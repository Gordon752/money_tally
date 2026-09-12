import '../domain/account.dart';
import '../domain/finance_data_set.dart';
import '../domain/sync_metadata.dart';
import '../domain/transaction.dart';

/// An unsaved replacement record, evaluated by the same account buckets as
/// Accounts. Nothing is written to the store, reservations, or sync history.
class TransactionAccountPreview {
  TransactionAccountPreview({
    required FinanceDataSet dataSet,
    required TransactionType type,
    required String accountId,
    required int amountMinor,
    required DateTime date,
    required TransactionStatus status,
    String? transferAccountId,
    TransactionRecord? replacing,
    DateTime? asOf,
  }) : asOf = asOf ?? DateTime.now(),
       _dataSet = dataSet.copyWith(
         transactions: [
           for (final record in dataSet.transactions)
             if (record.id != replacing?.id) record,
           TransactionRecord(
             id: replacing?.id ?? 'unsaved-transaction-preview',
             type: type,
             accountId: accountId,
             transferAccountId: transferAccountId,
             amountMinor: amountMinor.abs(),
             date: date,
             status: status,
             payee: '',
             sync: replacing?.sync ?? SyncMetadata.fresh(now: asOf),
           ),
         ],
       );

  final FinanceDataSet _dataSet;
  final DateTime asOf;

  int balanceMinor(String accountId) =>
      _dataSet.clearedBalanceForAccount(accountId, asOf: asOf);

  int pendingMinor(String accountId) =>
      _dataSet.pendingEffectForAccount(accountId, asOf: asOf);

  int futureMinor(String accountId) =>
      _dataSet.futureEffectForAccount(accountId, asOf: asOf);

  int economicBalanceMinor(String accountId) =>
      _dataSet.economicBalanceForAccount(accountId, asOf: asOf);

  /// Matches the account card metric: cleared plus pending, excluding future
  /// transactions. A positive card balance is issuer credit, not credit used.
  int? availableCreditMinor(AccountRecord account) {
    final limit = account.creditLimitMinor;
    if (account.type != AccountType.creditCard || limit == null) return null;
    final balance = economicBalanceMinor(account.id);
    return limit - (balance < 0 ? -balance : 0);
  }
}
