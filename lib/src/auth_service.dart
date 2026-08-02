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
  Future<void> signOut() async {}
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({firebase_auth.FirebaseAuth? auth})
    : _auth = auth ?? firebase_auth.FirebaseAuth.instance;

  final firebase_auth.FirebaseAuth _auth;

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
  Future<void> signOut() => _auth.signOut();
}

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
    super.key,
  });

  final AuthService authService;
  final FinanceRemoteRepository? remoteRepository;
  final FinanceRecordRepository? recordRepository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _initialSyncRetryDelay = Duration(milliseconds: 900);

  var _localOnly = false;
  var _isSigningIn = false;
  var _syncLabel = 'Synced';
  DateTime? _lastSuccessfulSyncAt;
  String? _authError;
  String? _syncingUid;
  String? _syncedUid;
  late final Stream<MoneyTallyUser?> _authStateStream;

  @override
  void initState() {
    super.initState();
    _authStateStream = widget.authService.authStateChanges();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localOnly) {
      FinanceDataStoreScope.read(context).detachRemoteSync();
      _syncedUid = null;
      _syncingUid = null;
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
          FinanceDataStoreScope.read(context).detachRemoteSync();
          _syncedUid = null;
          _syncingUid = null;
          return SignInView(
            isSigningIn: _isSigningIn,
            errorMessage: _authError,
            onAppleSignIn: _signInWithApple,
            onContinueLocal: () => setState(() => _localOnly = true),
          );
        }

        final dataStore = FinanceDataStoreScope.read(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncIfNeeded(user, dataStore);
        });
        return FinanceHome(
          syncLabel: user.isLocalOnly ? 'Local only' : _syncLabel,
          lastSuccessfulSyncLabel: _lastSuccessfulSyncAt == null
              ? null
              : '${shortDate(_lastSuccessfulSyncAt!.toLocal())} '
                    '${TimeOfDay.fromDateTime(_lastSuccessfulSyncAt!.toLocal()).format(context)}',
          onSyncNow: user.isLocalOnly ? null : () => _syncNow(user, dataStore),
          onSignOut: user.isLocalOnly ? null : widget.authService.signOut,
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

  void _syncIfNeeded(MoneyTallyUser user, FinanceDataStore dataStore) {
    final recordRepository = widget.recordRepository;
    if (user.isLocalOnly || recordRepository == null) {
      return;
    }
    if (_syncedUid == user.uid || _syncingUid == user.uid) return;

    _syncingUid = user.uid;
    unawaited(_syncUser(user.uid, recordRepository, dataStore));
  }

  Future<void> _syncUser(
    String userId,
    FinanceRecordRepository? recordRepository,
    FinanceDataStore dataStore, {
    bool retryAfterTransientFailure = true,
  }) async {
    try {
      if (recordRepository != null) {
        await dataStore.attachRemoteSync(
          remoteRepository: recordRepository,
          userId: userId,
        );
      }
      if (!mounted) return;
      setState(() {
        _syncedUid = userId;
        _syncingUid = null;
        _syncLabel = 'Synced';
        _lastSuccessfulSyncAt = DateTime.now();
      });
    } on Exception catch (error, stackTrace) {
      debugPrint('Cloud record sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      // On a cold start Firebase Auth can publish the restored user shortly
      // before Firestore has a usable session token. Retry once while keeping
      // the in-progress state; a persistent error still reaches the normal
      // Sync issue state below.
      if (retryAfterTransientFailure && _syncingUid == userId) {
        await Future<void>.delayed(_initialSyncRetryDelay);
        if (mounted && _syncingUid == userId) {
          return _syncUser(
            userId,
            recordRepository,
            dataStore,
            retryAfterTransientFailure: false,
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _syncingUid = null;
        _syncLabel = 'Sync issue';
      });
    }
  }

  Future<void> _syncNow(MoneyTallyUser user, FinanceDataStore dataStore) async {
    if (_syncingUid != null) return;
    setState(() {
      _syncedUid = null;
      _syncingUid = user.uid;
      _syncLabel = 'Syncing';
    });
    await _syncUser(user.uid, widget.recordRepository, dataStore);
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
