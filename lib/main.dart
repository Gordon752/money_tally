import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'firebase_options.dart';
import 'src/migration/v1_snapshot_migrator.dart';
import 'src/persistence/local_finance_data_set_repository.dart';

part 'src/app_theme.dart';
part 'src/auth_service.dart';
part 'src/domain.dart';
part 'src/finance_home.dart';
part 'src/finance_store.dart';
part 'src/firestore_finance_repository.dart';
part 'src/local_finance_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter startup error: ${details.exceptionAsString()}');
  };
  runApp(const MoneyTallyBootstrap());
}

class MoneyTallyBootstrap extends StatefulWidget {
  const MoneyTallyBootstrap({super.key});

  @override
  State<MoneyTallyBootstrap> createState() => _MoneyTallyBootstrapState();
}

class _MoneyTallyBootstrapState extends State<MoneyTallyBootstrap> {
  late final Future<FinanceStore> _startup = _load();

  Future<FinanceStore> _load() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return FinanceStore.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Money Tally',
      theme: AppTheme.light(),
      home: FutureBuilder<FinanceStore>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('Money Tally startup failed: ${snapshot.error}');
            return StartupErrorView(error: snapshot.error.toString());
          }
          final store = snapshot.data;
          if (store == null) {
            return const StartupLoadingView();
          }
          return MoneyTallyApp(
            store: store,
            authService: FirebaseAuthService(),
            remoteRepository: FirestoreFinanceRepository(),
          );
        },
      ),
    );
  }
}

class StartupLoadingView extends StatelessWidget {
  const StartupLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              color: AppTheme.accent,
              size: 48,
            ),
            SizedBox(height: 16),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Opening Money Tally',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class StartupErrorView extends StatelessWidget {
  const StartupErrorView({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppTheme.rose,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Money Tally could not start',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.rose,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MoneyTallyApp extends StatelessWidget {
  MoneyTallyApp({
    FinanceStore? store,
    AuthService? authService,
    this.remoteRepository,
    super.key,
  }) : store = store ?? FinanceStore.seeded(),
       authService = authService ?? LocalOnlyAuthService();

  final FinanceStore store;
  final AuthService authService;
  final FinanceRemoteRepository? remoteRepository;

  @override
  Widget build(BuildContext context) {
    return FinanceStoreScope(
      store: store,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Money Tally',
        theme: AppTheme.light(),
        home: AuthGate(
          authService: authService,
          remoteRepository: remoteRepository,
        ),
      ),
    );
  }
}
