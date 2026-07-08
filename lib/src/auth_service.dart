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
  var _localOnly = false;
  var _isSigningIn = false;
  var _syncLabel = 'Sync ready';
  String? _authError;
  String? _syncingUid;
  String? _syncedUid;
  FinanceStore? _listeningStore;
  FinanceRemoteRepository? _listeningRemoteRepository;
  String? _listeningUserId;
  Timer? _pushDebounce;
  late final Stream<MoneyTallyUser?> _authStateStream;

  @override
  void initState() {
    super.initState();
    _authStateStream = widget.authService.authStateChanges();
  }

  @override
  void dispose() {
    _detachStoreSync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localOnly) {
      _detachStoreSync();
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
          _detachStoreSync();
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

        final store = FinanceStoreScope.read(context);
        final dataStore = FinanceDataStoreScope.read(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncIfNeeded(user, store, dataStore);
        });
        return FinanceHome(
          syncLabel: user.isLocalOnly ? 'Local only' : _syncLabel,
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

  void _syncIfNeeded(
    MoneyTallyUser user,
    FinanceStore store,
    FinanceDataStore dataStore,
  ) {
    final remoteRepository = widget.remoteRepository;
    final recordRepository = widget.recordRepository;
    if (user.isLocalOnly ||
        (remoteRepository == null && recordRepository == null)) {
      return;
    }
    if (_syncedUid == user.uid || _syncingUid == user.uid) return;

    _syncingUid = user.uid;
    setState(() => _syncLabel = 'Syncing');
    unawaited(
      _syncUser(user.uid, remoteRepository, recordRepository, store, dataStore),
    );
  }

  Future<void> _syncUser(
    String userId,
    FinanceRemoteRepository? remoteRepository,
    FinanceRecordRepository? recordRepository,
    FinanceStore store,
    FinanceDataStore dataStore,
  ) async {
    try {
      if (remoteRepository != null) {
        final pulled = await store.pullSnapshot(
          remoteRepository: remoteRepository,
          userId: userId,
        );
        if (!pulled) {
          await store.pushSnapshot(
            remoteRepository: remoteRepository,
            userId: userId,
          );
        }
      }
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
      });
      if (remoteRepository != null) {
        _attachStoreSync(userId, remoteRepository, store);
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _syncingUid = null;
        _syncLabel = 'Sync issue';
      });
    }
  }

  void _attachStoreSync(
    String userId,
    FinanceRemoteRepository remoteRepository,
    FinanceStore store,
  ) {
    if (_listeningUserId == userId && _listeningStore == store) return;
    _detachStoreSync();
    _listeningUserId = userId;
    _listeningRemoteRepository = remoteRepository;
    _listeningStore = store;
    store.addListener(_queuePush);
  }

  void _detachStoreSync() {
    _pushDebounce?.cancel();
    _pushDebounce = null;
    _listeningStore?.removeListener(_queuePush);
    _listeningStore = null;
    _listeningRemoteRepository = null;
    _listeningUserId = null;
  }

  void _queuePush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 800), _pushLocalChanges);
  }

  Future<void> _pushLocalChanges() async {
    final store = _listeningStore;
    final remoteRepository = _listeningRemoteRepository;
    final userId = _listeningUserId;
    if (store == null || remoteRepository == null || userId == null) return;

    try {
      await store.pushSnapshot(
        remoteRepository: remoteRepository,
        userId: userId,
      );
      if (mounted && _syncLabel != 'Synced') {
        setState(() => _syncLabel = 'Synced');
      }
    } on Exception {
      if (mounted) setState(() => _syncLabel = 'Sync issue');
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: AppTheme.accent,
                    size: 52,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Money Tally',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.ink,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sign in to keep your accounts, ledgers, budgets, and scheduled transactions synced across iPhone, iPad, and Mac.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.ink.withValues(alpha: 0.7),
                      height: 1.35,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: isSigningIn ? null : onAppleSignIn,
                    icon: isSigningIn
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.apple),
                    label: Text(
                      isSigningIn ? 'Signing in' : 'Sign in with Apple',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: isSigningIn ? null : onContinueLocal,
                    child: const Text('Continue local-only'),
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
