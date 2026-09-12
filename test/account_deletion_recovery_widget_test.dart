import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' hide AccountType, SyncMetadata;
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';
import 'package:money_tally/src/sync/account_deletion_state.dart';
import 'package:money_tally/src/sync/automatic_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('deletion diagnostic exposes only bounded SDK codes', () {
    expect(
      accountDeletionDiagnosticCode('invalid-credential'),
      'invalid-credential',
    );
    expect(
      accountDeletionDiagnosticCode('token=secret@example.com'),
      'unknown',
    );
    expect(accountDeletionDiagnosticCode('x' * 81), 'unknown');
  });

  Future<FinanceDataStore> mount(WidgetTester tester, _Auth auth) async {
    final store = FinanceDataStore(
      dataSet: FinanceDataSet(
        accounts: [
          AccountRecord(
            id: 'test-account',
            name: 'Disposable',
            type: AccountType.checking,
            openingBalanceMinor: 100,
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
    await tester.pumpWidget(
      FinanceDataStoreScope(
        store: store,
        child: MaterialApp(
          home: AuthGate(
            authService: auth,
            automaticSyncScheduler: _Scheduler(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(store.dispose);
    return store;
  }

  testWidgets('unconfirmed deletion keeps local data and sync paused', (
    tester,
  ) async {
    final auth = _Auth();
    final store = await mount(tester, auth);
    final callback = tester
        .widget<FinanceHome>(find.byType(FinanceHome))
        .onDeleteAccount!;
    final outcome = expectLater(callback(), throwsA(isA<AuthException>()));
    await tester.pump();
    auth.result.completeError(const AuthException('Response lost.'));
    await outcome;
    await tester.pumpAndSettle();
    expect(store.accounts, hasLength(1));
    expect(await AccountDeletionState.pendingUser(), 'test-user');
    expect(auth.signOuts, 0);
    final home = tester.widget<FinanceHome>(find.byType(FinanceHome));
    expect(home.syncLabel, 'Deletion unconfirmed');
    expect(home.onSyncNow, isNull);
    expect(find.text('Account deletion not completed'), findsOneWidget);
    expect(find.text('Response lost.'), findsOneWidget);
  });

  testWidgets(
    'cancelling Apple verification preserves data and removes pause',
    (tester) async {
      final auth = _Auth()..sendRequest = false;
      final store = await mount(tester, auth);
      final callback = tester
          .widget<FinanceHome>(find.byType(FinanceHome))
          .onDeleteAccount!;
      final outcome = expectLater(callback(), throwsA(isA<AuthException>()));
      await tester.pump();
      auth.result.completeError(
        const AuthException('Cancelled', deletionNotStarted: true),
      );
      await outcome;
      await tester.pumpAndSettle();
      expect(store.accounts, hasLength(1));
      expect(await AccountDeletionState.pendingUser(), isNull);
      expect(auth.signOuts, 0);
      expect(find.text('Cancelled'), findsOneWidget);
    },
  );

  testWidgets(
    'pre-request failure remains visible after loading screen exits',
    (tester) async {
      final auth = _Auth()..sendRequest = false;
      final store = await mount(tester, auth);
      final outcome = expectLater(
        tester.widget<FinanceHome>(find.byType(FinanceHome)).onDeleteAccount!(),
        throwsA(isA<AuthException>()),
      );
      await tester.pump();
      expect(find.byType(FinanceHome), findsNothing);
      auth.result.completeError(
        const AuthException('Apple authorization revocation failed.'),
      );
      await outcome;
      await tester.pumpAndSettle();
      expect(
        find.text('Apple authorization revocation failed.'),
        findsOneWidget,
      );
      expect(store.accounts, hasLength(1));
      expect(auth.signOuts, 0);
      expect(await AccountDeletionState.pendingUser(), isNull);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(FinanceHome), findsOneWidget);
    },
  );

  testWidgets(
    'unexpected deletion error is visible and keeps recovery paused',
    (tester) async {
      final auth = _Auth();
      final store = await mount(tester, auth);
      final outcome = expectLater(
        tester.widget<FinanceHome>(find.byType(FinanceHome)).onDeleteAccount!(),
        throwsStateError,
      );
      await tester.pump();
      auth.result.completeError(StateError('sensitive internal exception'));
      await outcome;
      await tester.pumpAndSettle();
      expect(find.text('Account deletion not completed'), findsOneWidget);
      expect(find.textContaining('sensitive internal exception'), findsNothing);
      expect(store.accounts, hasLength(1));
      expect(await AccountDeletionState.pendingUser(), 'test-user');
      expect(
        tester.widget<FinanceHome>(find.byType(FinanceHome)).onSyncNow,
        isNull,
      );
    },
  );

  for (final requestWasSent in [false, true]) {
    testWidgets(
      'successful deletion retry clears previous error (request sent: $requestWasSent)',
      (tester) async {
        const failure = 'Apple authorization revocation failed.';
        final auth = _Auth()..sendRequest = requestWasSent;
        final store = await mount(tester, auth);
        final failed = expectLater(
          tester.widget<FinanceHome>(find.byType(FinanceHome)).onDeleteAccount!(),
          throwsA(isA<AuthException>()),
        );
        await tester.pump();
        auth.result.completeError(const AuthException(failure));
        await failed;
        await tester.pumpAndSettle();
        expect(find.text(failure), findsOneWidget);
        expect(store.accounts, hasLength(1));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        auth.result = Completer<void>();
        auth.sendRequest = true;
        auth.beforeSignOut = () => expect(store.accounts, isEmpty);
        final retry = tester
            .widget<FinanceHome>(find.byType(FinanceHome))
            .onDeleteAccount!();
        await tester.pump();
        auth.result.complete();
        await retry;
        await tester.pumpAndSettle();

        expect(auth.deleteCalls, 2);
        expect(auth.signOuts, 1);
        expect(store.accounts, isEmpty);
        expect(await AccountDeletionState.pendingUser(), isNull);
        expect(find.byType(SignInView), findsOneWidget);
        expect(find.text(failure), findsNothing);
        expect(find.text('Account deletion not completed'), findsNothing);
      },
    );
  }

  testWidgets('confirmed deletion clears local data before signing out', (
    tester,
  ) async {
    final auth = _Auth();
    final store = await mount(tester, auth);
    auth.beforeSignOut = () => expect(store.accounts, isEmpty);
    final deletion = tester
        .widget<FinanceHome>(find.byType(FinanceHome))
        .onDeleteAccount!();
    await tester.pump();
    auth.result.complete();
    await deletion;
    await tester.pumpAndSettle();
    expect(store.accounts, isEmpty);
    expect(auth.signOuts, 1);
    expect(await AccountDeletionState.pendingUser(), isNull);
    expect(find.byType(SignInView), findsOneWidget);
  });

  testWidgets(
    'confirmed deletion finishes local cleanup on restart without identity',
    (tester) async {
      await AccountDeletionState.begin('test-user');
      await AccountDeletionState.markRequestSent();
      await AccountDeletionState.markConfirmed();
      final auth = _Auth()..currentUser = null;
      final store = await mount(tester, auth);
      expect(store.accounts, isEmpty);
      expect(auth.signOuts, 1);
      expect(auth.deleteCalls, 0);
      expect(await AccountDeletionState.pendingUser(), isNull);
      expect(find.byType(SignInView), findsOneWidget);
    },
  );
}

class _Auth implements AuthService {
  @override
  MoneyTallyUser? currentUser = const MoneyTallyUser(
    uid: 'test-user',
    isLocalOnly: false,
  );
  var result = Completer<void>();
  bool sendRequest = true;
  int signOuts = 0;
  int deleteCalls = 0;
  void Function()? beforeSignOut;
  @override
  Stream<MoneyTallyUser?> authStateChanges() =>
      Stream.value(currentUser).asBroadcastStream();
  @override
  Future<MoneyTallyUser> signInWithApple() async => currentUser!;
  @override
  Future<void> deleteAccountWithApple() async {
    deleteCalls++;
    if (sendRequest) await AccountDeletionState.markRequestSent();
    await result.future;
  }

  @override
  Future<void> signOut() async {
    beforeSignOut?.call();
    signOuts++;
    currentUser = null;
  }
}

class _Scheduler implements AutomaticSyncTaskScheduler {
  @override
  Future<void> cancel() async {}
  @override
  Future<void> schedule({required int preferredMinutes, DateTime? now}) async {}
}
