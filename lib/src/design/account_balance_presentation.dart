import '../domain/account.dart';

/// Converts Trackmark's signed accounting balance into account-context copy.
///
/// Stored values remain signed: liabilities owed are negative, while a
/// positive credit-card balance means the issuer owes the user. This model is
/// presentation-only and must not be used for net-worth arithmetic.
class AccountBalancePresentation {
  const AccountBalancePresentation({
    required this.amountMinor,
    required this.isCredit,
    required this.needsAttention,
  });

  final int amountMinor;
  final bool isCredit;
  final bool needsAttention;

  String get suffix => isCredit ? 'credit' : '';
}

AccountBalancePresentation accountBalancePresentation(
  AccountType type,
  int signedBalanceMinor,
) {
  return switch (type) {
    AccountType.creditCard => AccountBalancePresentation(
      amountMinor: signedBalanceMinor.abs(),
      isCredit: signedBalanceMinor > 0,
      needsAttention: false,
    ),
    AccountType.loan => AccountBalancePresentation(
      amountMinor: signedBalanceMinor.abs(),
      isCredit: false,
      needsAttention: false,
    ),
    AccountType.checking ||
    AccountType.savings ||
    AccountType.cash ||
    AccountType.otherBanking => AccountBalancePresentation(
      amountMinor: signedBalanceMinor,
      isCredit: false,
      needsAttention: signedBalanceMinor < 0,
    ),
  };
}
