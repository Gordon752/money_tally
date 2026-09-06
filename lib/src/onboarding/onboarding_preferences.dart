import 'package:shared_preferences/shared_preferences.dart';

/// Advance only when a materially changed core workflow needs explaining.
const currentOnboardingVersion = 1;

/// Device-local UI state. Deliberately outside UserPreferences/FinanceDataSet:
/// those objects participate in financial backups and record synchronization.
class OnboardingPreferences {
  const OnboardingPreferences();

  static const storageKey = 'trackmark.onboardingVersionSeen';

  Future<int> readOnboardingVersionSeen() async {
    final storage = await SharedPreferences.getInstance();
    final value = storage.get(storageKey);
    return value is int && value >= 0 ? value : 0;
  }

  Future<void> complete() async {
    // A newer app's completion must not be downgraded by an older app.
    if (await readOnboardingVersionSeen() >= currentOnboardingVersion) return;
    await _write(currentOnboardingVersion);
  }

  Future<void> reset() => _write(0);

  Future<void> _write(int version) async {
    final storage = await SharedPreferences.getInstance();
    if (!await storage.setInt(storageKey, version)) {
      throw StateError('Could not save onboarding preferences.');
    }
  }
}
