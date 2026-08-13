import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../firebase_options.dart';
import '../domain/user_preferences.dart';
import '../migration/finance_data_bootstrapper.dart';
import '../persistence/firestore_record_repository.dart';
import '../persistence/automatic_backup_service.dart';
import 'cloud_sync_coordinator.dart';

const trackmarkDailySyncTaskIdentifier =
    'com.gordonbowles.moneytally.dailySync';

abstract interface class AutomaticSyncTaskScheduler {
  Future<void> schedule({required int preferredMinutes, DateTime? now});
  Future<void> cancel();
}

class WorkmanagerAutomaticSyncTaskScheduler
    implements AutomaticSyncTaskScheduler {
  const WorkmanagerAutomaticSyncTaskScheduler();

  @override
  Future<void> schedule({required int preferredMinutes, DateTime? now}) async {
    if (!Platform.isIOS) return;
    final anchor = now ?? DateTime.now();
    final next = AutomaticSyncPolicy.nextPreferredTime(
      now: anchor,
      preferredMinutes: preferredMinutes,
    );
    await Workmanager().registerPeriodicTask(
      trackmarkDailySyncTaskIdentifier,
      trackmarkDailySyncTaskIdentifier,
      frequency: const Duration(hours: 24),
      initialDelay: next.difference(anchor),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(),
    );
  }

  @override
  Future<void> cancel() async {
    if (!Platform.isIOS) return;
    await Workmanager().cancelByUniqueName(trackmarkDailySyncTaskIdentifier);
  }
}

abstract final class AutomaticSyncPolicy {
  static DateTime preferredTimeForDay({
    required DateTime day,
    required int preferredMinutes,
  }) {
    return DateTime(
      day.year,
      day.month,
      day.day,
      preferredMinutes ~/ 60,
      preferredMinutes % 60,
    );
  }

  static DateTime nextPreferredTime({
    required DateTime now,
    required int preferredMinutes,
  }) {
    final today = preferredTimeForDay(
      day: now,
      preferredMinutes: preferredMinutes,
    );
    if (today.isAfter(now)) return today;
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return preferredTimeForDay(
      day: tomorrow,
      preferredMinutes: preferredMinutes,
    );
  }

  static bool isCatchUpDue({
    required UserPreferences preferences,
    required DateTime now,
    required DateTime? lastSuccessfulSync,
  }) {
    if (!preferences.automaticSyncEnabled) return false;
    final windowStart = preferredTimeForDay(
      day: now,
      preferredMinutes: preferences.preferredDailySyncMinutes,
    );
    if (now.isBefore(windowStart)) return false;
    return lastSuccessfulSync == null ||
        lastSuccessfulSync.isBefore(windowStart);
  }
}

int? preferredAutomaticMaintenanceMinutes(UserPreferences preferences) {
  final enabled = <int>[
    if (preferences.automaticSyncEnabled) preferences.preferredDailySyncMinutes,
    if (preferences.automaticBackupsEnabled)
      preferences.preferredAutomaticBackupMinutes,
  ];
  if (enabled.isEmpty) return null;
  return enabled.reduce((a, b) => a < b ? a : b);
}

typedef AutomaticSyncOperation = Future<bool> Function();

/// Testable orchestration around the platform callback. The actual financial
/// merge remains exclusively inside CloudSyncCoordinator/FinanceDataStore.
Future<bool> runAutomaticSyncAttempt({
  required UserPreferences preferences,
  required String? userId,
  required DateTime now,
  required DateTime? lastSuccessfulSync,
  required AutomaticSyncOperation synchronize,
  required AutomaticSyncTaskScheduler scheduler,
}) async {
  if (!preferences.automaticSyncEnabled || userId == null) return true;
  try {
    if (!AutomaticSyncPolicy.isCatchUpDue(
      preferences: preferences,
      now: now,
      lastSuccessfulSync: lastSuccessfulSync,
    )) {
      return true;
    }
    return await synchronize();
  } finally {
    await scheduler.schedule(
      preferredMinutes: preferences.preferredDailySyncMinutes,
      now: now,
    );
  }
}

Future<void> initializeTrackmarkBackgroundSync() async {
  if (!Platform.isIOS) return;
  await Workmanager().initialize(trackmarkBackgroundCallbackDispatcher);
}

@pragma('vm:entry-point')
void trackmarkBackgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != trackmarkDailySyncTaskIdentifier) return true;
    DartPluginRegistrant.ensureInitialized();
    final scheduler = const WorkmanagerAutomaticSyncTaskScheduler();
    UserPreferences? loadedPreferences;
    var nextAttemptScheduled = false;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      final dataStore = await FinanceDataBootstrapper().loadStore();
      loadedPreferences = dataStore.preferences;
      final stateStore = const SyncExecutionStateStore();
      final now = DateTime.now();
      var succeeded = true;
      if (loadedPreferences.automaticBackupsEnabled) {
        try {
          await AutomaticBackupService().createIfDue(
            dataSet: dataStore.dataSet,
            now: now,
          );
        } on Object {
          succeeded = false;
        }
      }

      final user = FirebaseAuth.instance.currentUser;
      if (loadedPreferences.automaticSyncEnabled && user != null) {
        final lastSuccess = await stateStore.loadLastSuccessfulSync(user.uid);
        if (AutomaticSyncPolicy.isCatchUpDue(
          preferences: loadedPreferences,
          now: now,
          lastSuccessfulSync: lastSuccess,
        )) {
          final coordinator = CloudSyncCoordinator(
            recordRepository: FirestoreRecordRepository(),
            executionStateStore: stateStore,
          );
          succeeded =
              await coordinator.synchronize(
                userId: user.uid,
                dataStore: dataStore,
                timeout: const Duration(seconds: 25),
              ) &&
              succeeded;
          coordinator.dispose();
        }
      }
      final preferred = preferredAutomaticMaintenanceMinutes(loadedPreferences);
      if (preferred != null) {
        await scheduler.schedule(preferredMinutes: preferred, now: now);
      }
      nextAttemptScheduled = true;
      return succeeded;
    } on Object catch (error, stackTrace) {
      debugPrint('Automatic background sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      final preferred = loadedPreferences == null
          ? null
          : preferredAutomaticMaintenanceMinutes(loadedPreferences);
      if (preferred != null && !nextAttemptScheduled) {
        try {
          await scheduler.schedule(preferredMinutes: preferred);
        } on Object catch (error) {
          debugPrint('Could not reschedule automatic sync: $error');
        }
      }
    }
  });
}
