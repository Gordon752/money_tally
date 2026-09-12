import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local recovery state; not a server access-control mechanism.
class AccountDeletionState {
  static const _key = 'trackmark.accountDeletion';

  static Future<Map<String, dynamic>?> _read() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final value = preferences.getString(_key);
    if (value == null) return null;
    final state = jsonDecode(value) as Map<String, dynamic>;
    if (state['uid'] is! String || (state['uid'] as String).isEmpty) {
      throw StateError('Invalid account deletion recovery state.');
    }
    return state;
  }

  static Future<void> _write(Map<String, dynamic> state) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key, jsonEncode(state))) {
      throw StateError('Could not save account deletion recovery state.');
    }
  }

  static Future<String?> pendingUser() async =>
      (await _read())?['uid'] as String?;

  static Future<void> begin(String uid) async {
    final state = await _read();
    if (state != null) {
      if (state['uid'] != uid) {
        throw StateError('A previous account deletion needs recovery.');
      }
      return;
    }
    if (uid.isEmpty) throw ArgumentError.value(uid, 'uid');
    await _write({'uid': uid, 'requestSent': false, 'confirmed': false});
  }

  static Future<bool> requestWasSent() async =>
      (await _read())?['requestSent'] == true;

  static Future<bool> isConfirmed() async =>
      (await _read())?['confirmed'] == true;

  static Future<void> markRequestSent({bool sent = true}) async {
    final state = await _read();
    if (state == null) {
      throw StateError('Missing account deletion recovery state.');
    }
    state['requestSent'] = sent;
    await _write(state);
  }

  static Future<void> markConfirmed() async {
    final state = await _read();
    if (state == null) {
      throw StateError('Missing account deletion recovery state.');
    }
    state['confirmed'] = true;
    await _write(state);
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove(_key)) {
      throw StateError('Could not clear account deletion recovery state.');
    }
  }
}
