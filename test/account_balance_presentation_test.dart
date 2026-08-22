import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/design/account_balance_presentation.dart';
import 'package:money_tally/src/design/widgets/account_balance_text.dart';
import 'package:money_tally/src/design/widgets/account_card.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  test('account context converts debt without changing signed semantics', () {
    final card = accountBalancePresentation(AccountType.creditCard, -114486);
    expect(card.amountMinor, 114486);
    expect(card.isCredit, isFalse);
    expect(card.needsAttention, isFalse);

    final loan = accountBalancePresentation(AccountType.loan, -2500000);
    expect(loan.amountMinor, 2500000);
    expect(loan.isCredit, isFalse);
  });

  test('credit-card overpayment is explicit and assets remain signed', () {
    final credit = accountBalancePresentation(AccountType.creditCard, 5000);
    expect(credit.amountMinor, 5000);
    expect(credit.isCredit, isTrue);

    final overdrawn = accountBalancePresentation(AccountType.checking, -28742);
    expect(overdrawn.amountMinor, -28742);
    expect(overdrawn.needsAttention, isTrue);

    final restored = accountBalancePresentation(AccountType.checking, 0);
    expect(restored.needsAttention, isFalse);
  });

  test('net-worth accounting retains signed liability values', () {
    final store = FinanceDataStore(
      dataSet: FinanceDataSet(
        accounts: [
          AccountRecord(
            id: 'asset',
            name: 'Checking',
            type: AccountType.checking,
            openingBalanceMinor: 100000,
            sync: SyncMetadata.fresh(),
          ),
          AccountRecord(
            id: 'card',
            name: 'Card',
            type: AccountType.creditCard,
            openingBalanceMinor: -30000,
            sync: SyncMetadata.fresh(),
          ),
        ],
        categories: const [],
        transactions: const [],
        scheduledTransactions: const [],
        budgets: const [],
        preferences: const UserPreferences(),
      ),
    );

    expect(store.totalAssetsMinor, 100000);
    expect(store.totalLiabilitiesMinor, -30000);
    expect(store.netWorthMinor, 70000);
    expect(store.balanceForAccount('card'), -30000);
  });

  test('card credit is not treated as utilized credit', () {
    final store = FinanceDataStore(
      dataSet: FinanceDataSet(
        accounts: [
          AccountRecord(
            id: 'card-credit',
            name: 'Card',
            type: AccountType.creditCard,
            openingBalanceMinor: 5000,
            creditLimitMinor: 100000,
            sync: SyncMetadata.fresh(),
          ),
        ],
        categories: const [],
        transactions: const [],
        scheduledTransactions: const [],
        budgets: const [],
        preferences: const UserPreferences(),
      ),
    );

    expect(store.creditUsedMinorForAccount('card-credit'), 0);
    expect(store.creditAvailableMinorForAccount('card-credit'), 100000);
  });

  testWidgets('card debt is neutral and card credit is labeled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AccountBalanceText(
                accountType: AccountType.creditCard,
                signedBalanceMinor: -114486,
              ),
              AccountBalanceText(
                accountType: AccountType.creditCard,
                signedBalanceMinor: 5000,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text(r'$1,144.86'), findsOneWidget);
    expect(find.text(r'-$1,144.86'), findsNothing);
    expect(find.text(r'$50.00'), findsOneWidget);
    expect(find.text('credit'), findsOneWidget);
  });

  testWidgets('negative asset card adds text warning and clears at zero', (
    tester,
  ) async {
    final account = AccountRecord(
      id: 'checking',
      name: 'Checking',
      type: AccountType.checking,
      openingBalanceMinor: 0,
      sync: SyncMetadata.fresh(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountCard(account: account, balanceMinor: -28742),
        ),
      ),
    );
    expect(find.text(r'-$287.42'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AccountCard(account: account, balanceMinor: 0)),
      ),
    );
    expect(find.text('Needs attention'), findsNothing);
  });
}
