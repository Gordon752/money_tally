import 'dart:async';

class StaleSyncAttempt implements Exception {
  const StaleSyncAttempt();
}

/// Device-local lifetime of one sync attempt. Not financial/restore authority.
/// Zone propagation keeps checks attached to the original async continuation,
/// rather than accidentally consulting a replacement attempt's token.
class SyncAttemptAuthority {
  static final Object _zoneKey = Object();
  static SyncAttemptAuthority? get current =>
      Zone.current[_zoneKey] as SyncAttemptAuthority?;

  bool _valid = true;
  bool _timedOut = false;
  final Set<Future<void>> _effects = {};
  bool get isValid => _valid;
  bool get timedOut => _timedOut;
  void invalidate({bool timedOut = false}) {
    if (!_valid) return;
    _valid = false;
    _timedOut = timedOut;
  }

  void check() {
    if (!_valid) throw const StaleSyncAttempt();
  }

  static void checkCurrent() => current?.check();

  Future<T> run<T>(Future<T> Function() operation) =>
      runZoned(operation, zoneValues: {_zoneKey: this});

  /// Only for repairing a submitted local write with the CURRENT live data.
  /// The enclosing effect remains tracked until this repair settles. This
  /// must never be used to continue cloud work from an invalidated attempt.
  static Future<void> repairLocalWrite(Future<void> Function() repair) =>
      runZoned(repair, zoneValues: {_zoneKey: null});

  /// Submitted platform writes cannot be recalled. A replacement authority
  /// waits for these effects to settle; delayed reads need not block it.
  Future<void> drain() async {
    while (_effects.isNotEmpty) {
      await Future.wait(_effects.toList());
    }
  }

  static Future<T> effect<T>(Future<T> Function() operation) async {
    final authority = current;
    if (authority == null) return operation();
    authority.check();
    final settled = Completer<void>();
    authority._effects.add(settled.future);
    try {
      final result = await operation();
      authority.check();
      return result;
    } finally {
      authority._effects.remove(settled.future);
      settled.complete();
    }
  }
}
