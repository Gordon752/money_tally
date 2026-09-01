part of '../main.dart';

class MoneyTallyUser {
  const MoneyTallyUser({
    required this.uid,
    required this.isLocalOnly,
    this.email,
    this.displayName,
  });

  final String uid;
  final bool isLocalOnly;
  final String? email;
  final String? displayName;

  String get label {
    if (isLocalOnly) return 'Local only';
    return displayName ?? email ?? 'Signed in';
  }
}

abstract interface class AuthService {
  MoneyTallyUser? get currentUser;
  Stream<MoneyTallyUser?> authStateChanges();
  Future<MoneyTallyUser> signInWithApple();
  Future<void> deleteAccountWithApple();
  Future<void> signOut();
}

class LocalOnlyAuthService implements AuthService {
  LocalOnlyAuthService()
    : _user = const MoneyTallyUser(uid: 'local', isLocalOnly: true);

  final MoneyTallyUser _user;

  @override
  MoneyTallyUser get currentUser => _user;

  @override
  Stream<MoneyTallyUser?> authStateChanges() => Stream.value(_user);

  @override
  Future<MoneyTallyUser> signInWithApple() async => _user;

  @override
  Future<void> deleteAccountWithApple() async {
    throw const AuthException(
      'Account deletion is only available for a signed-in account.',
    );
  }

  @override
  Future<void> signOut() async {}
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    firebase_auth.FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? firebase_auth.FirebaseAuth.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final firebase_auth.FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  @override
  MoneyTallyUser? get currentUser => _auth.currentUser?.toMoneyTallyUser();

  @override
  Stream<MoneyTallyUser?> authStateChanges() {
    return _auth.authStateChanges().map((user) => user?.toMoneyTallyUser());
  }

  @override
  Future<MoneyTallyUser> signInWithApple() async {
    final rawNonce = _randomNonce();
    final nonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );
    final identityToken = appleCredential.identityToken;
    if (identityToken == null) {
      throw const AuthException('Apple did not return an identity token.');
    }

    final credential = firebase_auth.AppleAuthProvider.credentialWithIDToken(
      identityToken,
      rawNonce,
      firebase_auth.AppleFullPersonName(
        givenName: appleCredential.givenName,
        familyName: appleCredential.familyName,
      ),
    );
    final result = await _auth.signInWithCredential(credential);
    final user = result.user?.toMoneyTallyUser();
    if (user == null) {
      throw const AuthException('Apple sign-in did not finish.');
    }
    return user;
  }

  @override
  Future<void> deleteAccountWithApple() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw const AuthException(
        'Sign in again before deleting your Trackmark account.',
      );
    }

    try {
      final rawNonce = _randomNonce();
      final nonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      final identityToken = appleCredential.identityToken;
      if (identityToken == null) {
        throw const AuthException(
          'Apple could not verify the account deletion request.',
        );
      }
      final authorizationCode = appleCredential.authorizationCode.trim();
      if (authorizationCode.isEmpty) {
        throw const AuthException(
          'Apple did not authorize the account deletion request.',
        );
      }

      final credential = firebase_auth.AppleAuthProvider.credentialWithIDToken(
        identityToken,
        rawNonce,
        firebase_auth.AppleFullPersonName(
          givenName: appleCredential.givenName,
          familyName: appleCredential.familyName,
        ),
      );
      await currentUser.reauthenticateWithCredential(credential);
      await _auth.revokeTokenWithAuthorizationCode(authorizationCode);

      final result = await _functions
          .httpsCallable('deleteTrackmarkAccount')
          .call<Object?>();
      final data = result.data;
      if (data is! Map || data['deleted'] != true) {
        throw const AuthException(
          'Trackmark could not confirm that the account was deleted.',
        );
      }
      await _auth.signOut();
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const AuthException('Account deletion was cancelled.');
      }
      throw const AuthException(
        'Apple could not verify the account deletion request. Try again.',
      );
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw AuthException(_accountDeletionAuthMessage(error.code));
    } on FirebaseFunctionsException catch (error) {
      throw AuthException(_accountDeletionCloudMessage(error.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

String _accountDeletionAuthMessage(String code) => switch (code) {
  'requires-recent-login' =>
    'Apple needs you to sign in again before deleting this account.',
  'network-request-failed' =>
    'Trackmark could not reach Apple. Check your connection and try again.',
  _ => 'Trackmark could not delete the account. Try again.',
};

String _accountDeletionCloudMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your sign-in expired. Sign in again before deleting the account.',
  'unavailable' || 'deadline-exceeded' =>
    'Trackmark cloud is temporarily unavailable. Nothing was deleted.',
  _ => 'Trackmark could not delete the cloud account. Nothing was deleted.',
};

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension on firebase_auth.User {
  MoneyTallyUser toMoneyTallyUser() {
    return MoneyTallyUser(
      uid: uid,
      isLocalOnly: false,
      email: email,
      displayName: displayName,
    );
  }
}

String _randomNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.authService,
    this.remoteRepository,
    this.recordRepository,
    this.automaticSyncScheduler = const WorkmanagerAutomaticSyncTaskScheduler(),
    super.key,
  });

  final AuthService authService;
  final FinanceRemoteRepository? remoteRepository;
  final FinanceRecordRepository? recordRepository;
  final AutomaticSyncTaskScheduler automaticSyncScheduler;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  var _localOnly = false;
  var _isSigningIn = false;
  String? _authError;
  String? _syncedUid;
  String? _autoSyncAttemptedUid;
  String? _loadedSyncStateUid;
  String? _automaticSyncConfiguration;
  String? _foregroundCatchUpAttempt;
  var _isDeletingAccount = false;
  FinanceDataStore? _currentDataStore;
  MoneyTallyUser? _currentUser;
  CloudSyncCoordinator? _syncCoordinator;
  final AutomaticBackupService _automaticBackupService =
      AutomaticBackupService();
  late final Stream<MoneyTallyUser?> _authStateStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStateStream = widget.authService.authStateChanges();
    final repository = widget.recordRepository;
    if (repository != null) {
      _syncCoordinator = CloudSyncCoordinator(recordRepository: repository)
        ..addListener(_handleSyncStateChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _currentDataStore?.removeListener(_handleDataStoreChanged);
    _syncCoordinator
      ?..removeListener(_handleSyncStateChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foregroundCatchUpAttempt = null;
      final user = _currentUser;
      final store = _currentDataStore;
      if (store != null) {
        unawaited(_runAutomaticBackupCatchUp(store));
      }
      if (user != null && store != null && !user.isLocalOnly) {
        unawaited(_refreshSyncStateAndCatchUp(user, store));
      }
    }
  }

  Future<void> _refreshSyncStateAndCatchUp(
    MoneyTallyUser user,
    FinanceDataStore dataStore,
  ) async {
    await _syncCoordinator?.loadStateForUser(user.uid, force: true);
    await _runForegroundCatchUp(user, dataStore);
  }

  void _handleSyncStateChanged() {
    if (mounted) setState(() {});
  }

  void _handleDataStoreChanged() {
    final user = _currentUser;
    final dataStore = _currentDataStore;
    if (dataStore == null) return;
    unawaited(_configureAutomaticSync(dataStore.preferences));
    unawaited(_runAutomaticBackupCatchUp(dataStore));
    if (user != null && !user.isLocalOnly) {
      unawaited(_runForegroundCatchUp(user, dataStore));
    }
  }

  void _bindDataStore(FinanceDataStore? dataStore) {
    if (identical(_currentDataStore, dataStore)) return;
    _currentDataStore?.removeListener(_handleDataStoreChanged);
    _currentDataStore = dataStore;
    dataStore?.addListener(_handleDataStoreChanged);
  }

  @override
  Widget build(BuildContext context) {
    if (_localOnly) {
      final dataStore = FinanceDataStoreScope.read(context);
      dataStore.detachRemoteSync();
      _syncedUid = null;
      _autoSyncAttemptedUid = null;
      _loadedSyncStateUid = null;
      _currentUser = null;
      _bindDataStore(dataStore);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_configureAutomaticSync(dataStore.preferences));
        unawaited(_runAutomaticBackupCatchUp(dataStore));
      });
      return const FinanceHome(syncLabel: 'Local only');
    }

    return StreamBuilder<MoneyTallyUser?>(
      stream: _authStateStream,
      initialData: widget.authService.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting &&
            user == null) {
          return const _FullScreenProgress(message: 'Checking sign-in');
        }
        if (user == null) {
          final dataStore = FinanceDataStoreScope.read(context);
          dataStore.detachRemoteSync();
          _syncedUid = null;
          _autoSyncAttemptedUid = null;
          _loadedSyncStateUid = null;
          _currentUser = null;
          _bindDataStore(dataStore);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(_configureAutomaticSync(dataStore.preferences));
            unawaited(_runAutomaticBackupCatchUp(dataStore));
          });
          return SignInView(
            isSigningIn: _isSigningIn,
            errorMessage: _authError,
            onAppleSignIn: _signInWithApple,
            onContinueLocal: () => setState(() => _localOnly = true),
          );
        }

        final dataStore = FinanceDataStoreScope.read(context);
        _currentUser = user;
        _bindDataStore(dataStore);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_prepareSignedInExperience(user, dataStore));
        });
        final coordinator = _syncCoordinator;
        final syncLabel = user.isLocalOnly
            ? 'Local only'
            : switch (coordinator?.status) {
                CloudSyncStatus.syncing => 'Syncing',
                CloudSyncStatus.issue => 'Sync issue',
                _ => 'Synced',
              };
        final lastSuccessfulSyncAt = coordinator?.lastSuccessfulSyncAt;
        return FinanceHome(
          syncLabel: syncLabel,
          syncErrorLabel: coordinator?.lastErrorDescription,
          syncDiagnosticLabel: coordinator?.lastDiagnostic?.conciseDescription,
          lastSuccessfulSyncLabel: lastSuccessfulSyncAt == null
              ? null
              : '${shortDate(lastSuccessfulSyncAt.toLocal())} '
                    '${TimeOfDay.fromDateTime(lastSuccessfulSyncAt.toLocal()).format(context)}',
          onSyncNow: user.isLocalOnly ? null : () => _syncNow(user, dataStore),
          onSignOut: user.isLocalOnly ? null : widget.authService.signOut,
          onDeleteAccount: user.isLocalOnly
              ? null
              : () => _deleteAccount(user, dataStore),
        );
      },
    );
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _authError = null;
      _isSigningIn = true;
    });
    try {
      await widget.authService.signInWithApple();
    } on Exception catch (error) {
      debugPrint('Apple sign-in failed: $error');
      if (!mounted) return;
      final message = error.toString();
      setState(() => _authError = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _prepareSignedInExperience(
    MoneyTallyUser user,
    FinanceDataStore dataStore,
  ) async {
    final coordinator = _syncCoordinator;
    if (user.isLocalOnly || coordinator == null) return;
    if (_loadedSyncStateUid != user.uid) {
      _loadedSyncStateUid = user.uid;
      await coordinator.loadStateForUser(user.uid);
    }
    await _configureAutomaticSync(dataStore.preferences);
    var attemptedInitialSync = false;
    if (_syncedUid != user.uid && _autoSyncAttemptedUid != user.uid) {
      attemptedInitialSync = true;
      _autoSyncAttemptedUid = user.uid;
      final succeeded = await coordinator.synchronize(
        userId: user.uid,
        dataStore: dataStore,
        retryAfterTransientFailure: true,
        trigger: CloudSyncTrigger.initial,
      );
      if (succeeded) _syncedUid = user.uid;
    }
    if (!attemptedInitialSync) {
      await _runForegroundCatchUp(user, dataStore);
    }
  }

  Future<void> _configureAutomaticSync(UserPreferences preferences) async {
    final signature =
        '${preferences.automaticSyncEnabled}:${preferences.preferredDailySyncMinutes}:'
        '${preferences.automaticBackupsEnabled}:${preferences.preferredAutomaticBackupMinutes}';
    if (_automaticSyncConfiguration == signature) return;
    try {
      final preferred = preferredAutomaticMaintenanceMinutes(preferences);
      if (preferred != null) {
        await widget.automaticSyncScheduler.schedule(
          preferredMinutes: preferred,
        );
      } else {
        await widget.automaticSyncScheduler.cancel();
      }
      _automaticSyncConfiguration = signature;
    } on Object catch (error) {
      debugPrint('Could not update automatic sync schedule: $error');
    }
  }

  Future<void> _runAutomaticBackupCatchUp(FinanceDataStore dataStore) async {
    try {
      await _automaticBackupService.createIfDue(
        dataSet: dataStore.dataSet,
        now: DateTime.now(),
      );
    } on Object catch (error) {
      debugPrint('Automatic backup failed: $error');
    }
  }

  Future<void> _runForegroundCatchUp(
    MoneyTallyUser user,
    FinanceDataStore dataStore,
  ) async {
    final coordinator = _syncCoordinator;
    if (coordinator == null || user.isLocalOnly || coordinator.isSyncing) {
      return;
    }
    final now = DateTime.now();
    final preferences = dataStore.preferences;
    if (!AutomaticSyncPolicy.isCatchUpDue(
      preferences: preferences,
      now: now,
      lastSuccessfulSync: coordinator.lastSuccessfulSyncAt,
    )) {
      return;
    }
    final window = AutomaticSyncPolicy.preferredTimeForDay(
      day: now,
      preferredMinutes: preferences.preferredDailySyncMinutes,
    ).toIso8601String();
    if (_foregroundCatchUpAttempt == window) return;
    _foregroundCatchUpAttempt = window;
    await coordinator.synchronize(
      userId: user.uid,
      dataStore: dataStore,
      trigger: CloudSyncTrigger.foregroundCatchUp,
    );
  }

  Future<void> _syncNow(MoneyTallyUser user, FinanceDataStore dataStore) async {
    final coordinator = _syncCoordinator;
    if (coordinator == null || coordinator.isSyncing) return;
    _syncedUid = null;
    final succeeded = await coordinator.synchronize(
      userId: user.uid,
      dataStore: dataStore,
      trigger: CloudSyncTrigger.manual,
    );
    if (!mounted) return;
    if (!succeeded) {
      final message = coordinator.lastErrorDescription ?? 'Cloud sync failed';
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    _syncedUid = user.uid;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 10),
              Text('Sync completed'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _deleteAccount(
    MoneyTallyUser user,
    FinanceDataStore dataStore,
  ) async {
    if (_isDeletingAccount) return;
    final coordinator = _syncCoordinator;
    if (coordinator?.isSyncing == true) {
      throw const AuthException(
        'Wait for cloud sync to finish before deleting the account.',
      );
    }

    _isDeletingAccount = true;
    try {
      await widget.authService.deleteAccountWithApple();

      dataStore.detachRemoteSync();
      coordinator?.reset();
      await widget.automaticSyncScheduler.cancel();

      try {
        await dataStore.resetTrackmarkData(resetAppSettings: true);
      } on Object {
        // The server-side account deletion has already completed. Removing
        // the durable local snapshot is the final safety net if notification
        // reconciliation or another device-only cleanup step fails.
        await dataStore.localRepository?.clear();
      }

      await dataStore.localRepository?.clearAcknowledgedRestoreGeneration(
        user.uid,
      );
      final repository = widget.recordRepository;
      if (repository case final DeletedAccountLocalStateCleaner cleaner) {
        await cleaner.clearDeletedAccountLocalState(user.uid);
      }
      await coordinator?.executionStateStore.clearForDeletedUser(user.uid);

      _syncedUid = null;
      _autoSyncAttemptedUid = null;
      _loadedSyncStateUid = null;
      _automaticSyncConfiguration = null;
      _foregroundCatchUpAttempt = null;
    } finally {
      _isDeletingAccount = false;
    }
  }
}

class SignInView extends StatelessWidget {
  const SignInView({
    required this.isSigningIn,
    required this.errorMessage,
    required this.onAppleSignIn,
    required this.onContinueLocal,
    super.key,
  });

  final bool isSigningIn;
  final String? errorMessage;
  final VoidCallback onAppleSignIn;
  final VoidCallback onContinueLocal;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? TrackmarkBrandPalette.deepGreen
        : TrackmarkBrandPalette.ivory;
    final primaryText = isDark
        ? TrackmarkBrandPalette.warmWhite
        : TrackmarkBrandPalette.deepGreen;
    final secondaryText = isDark
        ? TrackmarkBrandPalette.paleGold
        : TrackmarkBrandPalette.deepGreen.withValues(alpha: 0.72);
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(
                alignment: const Alignment(0, -0.30),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: TrackmarkBrandLockup(
                          bright: isDark,
                          markSize: 160,
                          wordmarkSize: 32,
                        ),
                      ),
                      const SizedBox(height: 46),
                      Text(
                        'Manage your money with confidence.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: primaryText,
                          height: 1.3,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Securely sync your data across your Apple devices.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryText,
                          height: 1.42,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 44),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: isDark
                              ? TrackmarkBrandPalette.warmWhite
                              : TrackmarkBrandPalette.deepGreen,
                          foregroundColor: isDark
                              ? TrackmarkBrandPalette.deepGreen
                              : TrackmarkBrandPalette.ivory,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: isSigningIn ? null : onAppleSignIn,
                        icon: isSigningIn
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(AppIcon.apple),
                        label: Text(
                          isSigningIn ? 'Signing in' : 'Sign in with Apple',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          foregroundColor: primaryText,
                          side: BorderSide(
                            color: isDark
                                ? TrackmarkBrandPalette.paleGold
                                : TrackmarkBrandPalette.deepGreen,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: isSigningIn ? null : onContinueLocal,
                        child: const Text(
                          'Continue Local-Only',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTheme.rose.withValues(alpha: 0.08),
                            border: Border.all(
                              color: AppTheme.rose.withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(
                                color: AppTheme.rose,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenProgress extends StatelessWidget {
  const _FullScreenProgress({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
