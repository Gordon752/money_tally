import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as app;
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/migration/v1_snapshot_migrator.dart';
import 'package:money_tally/src/onboarding/onboarding_preferences.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_restore_service.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _continue = ValueKey('onboarding-continue');
const _back = ValueKey('onboarding-back');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('onboarding v1 defaults to zero and preserves newer versions', () async {
    const preferences = OnboardingPreferences();
    expect(currentOnboardingVersion, 1);
    expect(await preferences.readOnboardingVersionSeen(), 0);
    await preferences.complete();
    expect(await preferences.readOnboardingVersionSeen(), 1);
    final storage = await SharedPreferences.getInstance();
    await storage.setInt(OnboardingPreferences.storageKey, 2);
    await preferences.complete();
    expect(await preferences.readOnboardingVersionSeen(), 2);
    await preferences.reset();
    expect(await preferences.readOnboardingVersionSeen(), 0);
  });

  for (final version in [0, currentOnboardingVersion]) {
    testWidgets('preloaded launch version $version selects the first frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: app.OnboardingGate(
            initialVersionSeen: version,
            child: const Scaffold(body: Text('Main app')),
          ),
        ),
      );
      expect(
        find.text('Welcome to Trackmark Money'),
        version == 0 ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Main app'),
        version == 0 ? findsNothing : findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }

  testWidgets('leaving partway through does not mark onboarding completed', (
    tester,
  ) async {
    await _gate(tester);
    await _tap(tester, find.byKey(_continue));
    await _tap(tester, find.byKey(_continue));
    await tester.pumpWidget(const SizedBox());
    expect(await const OnboardingPreferences().readOnboardingVersionSeen(), 0);
    await _gate(tester);
    expect(find.text('Welcome to Trackmark Money'), findsOneWidget);
  });

  for (final value in [
    null,
    -1,
    0,
    currentOnboardingVersion,
    currentOnboardingVersion + 1,
  ]) {
    testWidgets('launch eligibility for stored onboarding version $value', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        OnboardingPreferences.storageKey: ?value,
      });
      await _gate(tester);
      final eligible = (value ?? 0) < currentOnboardingVersion;
      expect(
        find.text('Welcome to Trackmark Money'),
        eligible ? findsOneWidget : findsNothing,
      );
      expect(find.text('Main app'), eligible ? findsNothing : findsOneWidget);
    });
  }

  testWidgets(
    'fresh application shows onboarding before sign-in; no setup/data changes',
    (tester) async {
      final store = FinanceDataStore(
        dataSet: const FinanceDataSet(
          accounts: [],
          categories: [],
          transactions: [],
          scheduledTransactions: [],
          budgets: [],
          preferences: UserPreferences(),
        ),
      );
      final before = store.dataSet.toJson();
      final auth = _SignedOutAuth();
      await tester.pumpWidget(
        app.MoneyTallyApp(dataStore: store, authService: auth),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Trackmark Money'), findsOneWidget);
      expect(find.text('Sign in with Apple'), findsNothing);
      expect(auth.subscriptions, 0);
      await _ready(tester);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        0,
      );
      await _tap(tester, find.byKey(_continue));
      expect(find.text('Sign in with Apple'), findsOneWidget);
      expect(find.text('Continue Local-Only'), findsOneWidget);
      expect(auth.subscriptions, 1);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        currentOnboardingVersion,
      );
      expect(store.dataSet.toJson(), before);
    },
  );

  testWidgets(
    'Back/Continue preserve exactly five pages and only Start completes',
    (tester) async {
      await _gate(tester);
      expect(find.text('1 of 5'), findsOneWidget);
      expect(find.byKey(_back), findsNothing);
      await _tap(tester, find.byKey(_continue));
      expect(find.text('2 of 5'), findsOneWidget);
      expect(find.text('Know what your money is doing'), findsOneWidget);
      await _tap(tester, find.byKey(_back));
      expect(find.text('1 of 5'), findsOneWidget);
      await _ready(tester);
      expect(find.text('5 of 5'), findsOneWidget);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        0,
      );
      await _tap(tester, find.byKey(_continue));
      expect(find.text('Main app'), findsOneWidget);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        currentOnboardingVersion,
      );
      await tester.pumpWidget(const SizedBox());
      await _gate(tester);
      expect(find.text('Main app'), findsOneWidget);
      expect(find.byType(app.TrackmarkOnboarding), findsNothing);
    },
  );

  testWidgets(
    'Screen 2 uses the requested Balance/Pending/Reserved definitions only',
    (tester) async {
      await _gate(tester);
      await _tap(tester, find.byKey(_continue));
      for (final copy in [
        'Cleared money currently in the account.',
        'Transactions that are known but not cleared yet. Pending affects Available to Spend, but does not change Balance until the transaction is cleared. It does not affect Reserved.',
        'Money assigned to Funds or Goals. Reserved reduces Available to Spend, but does not change Balance until that money is actually spent.',
        'Money still free after pending commitments and reservations.',
        'The money doesn’t move. Its job changes.',
      ]) {
        expect(find.textContaining(copy, findRichText: true), findsOneWidget);
      }
      expect(
        find.text('Money you know about that has not cleared yet.'),
        findsNothing,
      );
      expect(find.text(r'Starting balance: $2,000'), findsOneWidget);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        0,
      );
      expect(currentOnboardingVersion, 1);
    },
  );

  testWidgets(
    'View Guides opens the shared guide and returns to Ready without completing',
    (tester) async {
      await _gate(tester);
      await _ready(tester);
      await _tap(tester, find.byKey(const ValueKey('onboarding-guides')));
      expect(find.byType(app.TrackmarkGuidesPage), findsOneWidget);
      expect(find.text('Help & Guides'), findsOneWidget);
      expect(
        find.text('Money you know about that has not cleared yet.'),
        findsOneWidget,
      );
      expect(find.text('Money assigned to Funds or Goals.'), findsOneWidget);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        0,
      );
      await _tap(tester, find.byTooltip('Back'));
      expect(find.text('You’re ready'), findsOneWidget);
      await _tap(tester, find.byKey(_continue));
      expect(find.text('Main app'), findsOneWidget);
    },
  );

  testWidgets(
    'failed completion stays on Ready and can retry without losing progress',
    (tester) async {
      final preferences = _FailOncePreferences();
      await _gate(tester, preferences: preferences);
      await _ready(tester);
      await _tap(tester, find.byKey(_continue));
      expect(
        find.text('Your progress could not be saved. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('You’re ready'), findsOneWidget);
      expect(await preferences.readOnboardingVersionSeen(), 0);
      await _tap(tester, find.byKey(_continue));
      expect(find.text('Main app'), findsOneWidget);
      expect(await preferences.readOnboardingVersionSeen(), 1);
    },
  );

  test(
    'onboarding is absent from financial backup, restore, and local data records',
    () async {
      final store = _store();
      final original = store.dataSet.toJson();
      final before = const BackupCodec().encodeJson(
        store.dataSet,
        exportedAt: DateTime(2026, 9, 6),
      );
      await const OnboardingPreferences().complete();
      final after = const BackupCodec().encodeJson(
        store.dataSet,
        exportedAt: DateTime(2026, 9, 6),
      );
      expect(after, before);
      expect(after, isNot(contains('onboarding')));
      expect(jsonDecode(after)['schemaVersion'], 7);
      final restored = const BackupRestoreValidator().validate(after);
      await store.restoreBackupDataSet(restored.dataSet);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        1,
      );
      const repository = LocalFinanceDataSetRepository(
        storageKey: 'onboarding-finance-fixture',
      );
      await repository.save(store.dataSet);
      expect((await repository.load())!.toJson(), original);
      expect(
        (await SharedPreferences.getInstance()).getKeys(),
        containsAll([OnboardingPreferences.storageKey, repository.storageKey]),
      );
    },
  );

  testWidgets(
    'Reset Data with preferences preserved does not replay onboarding',
    (tester) async {
      final store = _store();
      await const OnboardingPreferences().complete();
      await store.resetTrackmarkData();
      expect(store.accounts, isEmpty);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        1,
      );
      await _gate(tester);
      expect(find.text('Main app'), findsOneWidget);
    },
  );

  testWidgets(
    'Reset Preferences preserves financial records/payees and replays on next launch',
    (tester) async {
      final store = _store();
      await store.savePreferences(
        store.preferences.copyWith(
          appearanceMode: AppearanceMode.dark,
          launchScreen: LaunchScreen.accounts,
          showLedgerIcons: true,
          savedPayeeNames: ['Cafe', 'Old Cafe'],
          archivedPayeeNames: {'old cafe'},
          deletedPayeeNames: {'closed cafe'},
        ),
      );
      final before = store.dataSet.toJson();
      final payees = store.preferences;
      await const OnboardingPreferences().complete();
      await app.resetTrackmarkPreferences(store);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        0,
      );
      expect(store.preferences.appearanceMode, AppearanceMode.system);
      expect(store.preferences.showLedgerIcons, isFalse);
      expect(store.preferences.launchScreen, LaunchScreen.dashboard);
      expect(store.preferences.savedPayeeNames, payees.savedPayeeNames);
      expect(store.preferences.archivedPayeeNames, payees.archivedPayeeNames);
      expect(store.preferences.deletedPayeeNames, payees.deletedPayeeNames);
      expect(store.preferences.payeeCatalogStates, payees.payeeCatalogStates);
      expect(store.dataSet.copyWith(preferences: payees).toJson(), before);
      await _gate(tester);
      expect(find.text('Welcome to Trackmark Money'), findsOneWidget);
    },
  );

  testWidgets(
    'Replay Onboarding can close early and return to the same Settings state',
    (tester) async {
      await const OnboardingPreferences().complete();
      final store = _store();
      final before = store.dataSet.toJson();
      await _settings(tester, store);
      final settingsState = tester.state(find.byType(app.SettingsView));
      await _tap(
        tester,
        find.byKey(const ValueKey('settings-replay-onboarding')),
      );
      expect(find.text('Welcome to Trackmark Money'), findsOneWidget);
      await _tap(tester, find.byKey(_continue));
      expect(find.text('2 of 5'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('onboarding-close')));
      expect(find.byType(app.TrackmarkOnboarding), findsNothing);
      expect(tester.state(find.byType(app.SettingsView)), same(settingsState));
      expect(store.dataSet.toJson(), before);
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        1,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('settings-replay-onboarding')),
      );
      expect(find.text('1 of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final version in [null, 0, currentOnboardingVersion, 2]) {
    testWidgets('Replay completion preserves all state with version $version', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        OnboardingPreferences.storageKey: ?version,
        'unrelated-device-preference': 'unchanged',
      });
      final store = _store();
      await store.savePreferences(
        store.preferences.copyWith(
          appearanceMode: AppearanceMode.dark,
          showLedgerIcons: true,
          notificationsEnabled: true,
          automaticSyncEnabled: true,
          automaticBackupsEnabled: true,
        ),
      );
      final storage = await SharedPreferences.getInstance();
      final beforeLocal = {
        for (final key in storage.getKeys()) key: storage.get(key),
      };
      final beforeFinance = store.dataSet.toJson();
      await _settings(tester, store);
      await _tap(
        tester,
        find.byKey(const ValueKey('settings-replay-onboarding')),
      );
      await _ready(tester);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Start Using Trackmark'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('onboarding-guides')));
      expect(find.byType(app.TrackmarkGuidesPage), findsOneWidget);
      await _tap(tester, find.byTooltip('Back'));
      expect(find.text('5 of 5'), findsOneWidget);
      await _tap(tester, find.byKey(_continue));
      expect(find.byType(app.TrackmarkOnboarding), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-replay-onboarding')),
        findsOneWidget,
      );
      expect(store.dataSet.toJson(), beforeFinance);
      expect({
        for (final key in storage.getKeys()) key: storage.get(key),
      }, beforeLocal);
      expect(currentOnboardingVersion, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Replay system Back goes to the previous page, then Settings', (
    tester,
  ) async {
    await _settings(tester, _store());
    await _tap(
      tester,
      find.byKey(const ValueKey('settings-replay-onboarding')),
    );
    await _tap(tester, find.byKey(_continue));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 of 5'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(app.TrackmarkOnboarding), findsNothing);
    expect(find.byType(app.SettingsView), findsOneWidget);
    expect(await const OnboardingPreferences().readOnboardingVersionSeen(), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Settings provides Guides and a confirmed financial-data-safe preferences reset',
    (tester) async {
      await const OnboardingPreferences().complete();
      final store = _store();
      final before = store.dataSet.toJson();
      await tester.pumpWidget(
        FinanceDataStoreScope(
          store: store,
          child: MaterialApp(
            theme: app.AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: app.SettingsView()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<app.TrackmarkSupportLinkRow>(
              find.byKey(const ValueKey('settings-help-guides')),
            )
            .title,
        'Help & Guides',
      );
      expect(find.byType(app.TrackmarkGuidesPage), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('data-management-row')));
      await _tap(tester, find.byKey(const ValueKey('reset-preferences-row')));
      expect(find.text('Reset Preferences?'), findsOneWidget);
      await _tap(tester, find.text('Cancel'));
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        1,
      );
      expect(store.dataSet.toJson(), before);
      await _tap(tester, find.byKey(const ValueKey('reset-preferences-row')));
      await _tap(
        tester,
        find.byKey(const ValueKey('confirm-reset-preferences')),
      );
      expect(
        await const OnboardingPreferences().readOnboardingVersionSeen(),
        0,
      );
      expect(
        store.dataSet
            .copyWith(preferences: FinanceDataSet.fromJson(before).preferences)
            .toJson(),
        before,
      );
      expect(
        find.text(
          'Preferences reset. The introduction will appear on your next launch.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

FinanceDataStore _store() {
  final dataSet = const V1SnapshotMigrator().migrate(
    app.FinanceStore.seeded().snapshot().toJson(),
  );
  return FinanceDataStore(
    dataSet: dataSet.copyWith(
      preferences: dataSet.preferences.copyWith(
        legacyV1MigrationCompleted: true,
      ),
    ),
  );
}

Future<void> _settings(WidgetTester tester, FinanceDataStore store) async {
  await tester.pumpWidget(
    FinanceDataStoreScope(
      store: store,
      child: MaterialApp(
        theme: app.AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: app.SettingsView()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _gate(
  WidgetTester tester, {
  OnboardingPreferences preferences = const OnboardingPreferences(),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: app.AppTheme.light(),
      home: app.OnboardingGate(
        preferences: preferences,
        child: const Scaffold(body: Text('Main app')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _ready(WidgetTester tester) async {
  for (var page = 0; page < 4; page++) {
    await _tap(tester, find.byKey(_continue));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _FailOncePreferences extends OnboardingPreferences {
  var failed = false;
  @override
  Future<void> complete() async {
    if (!failed) {
      failed = true;
      throw StateError('Simulated device preference failure');
    }
    await super.complete();
  }
}

class _SignedOutAuth implements app.AuthService {
  var subscriptions = 0;
  @override
  app.MoneyTallyUser? get currentUser => null;
  @override
  Stream<app.MoneyTallyUser?> authStateChanges() {
    subscriptions++;
    return Stream.value(null);
  }

  @override
  Future<void> deleteAccountWithApple() async => throw UnimplementedError();
  @override
  Future<void> signOut() async {}
  @override
  Future<app.MoneyTallyUser> signInWithApple() async =>
      throw UnimplementedError();
}
