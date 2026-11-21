import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the login session in the phone's secure keystore (Android Keystore,
/// iOS Keychain) instead of plain app preferences.
///
/// Existing sessions are moved across on first launch, so nobody is signed
/// out by this change. On web the browser's own storage is used.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey});

  final String persistSessionKey;
  final _secure = const FlutterSecureStorage();
  String? _cached;

  @override
  Future<void> initialize() async {
    try {
      _cached = await _secure.read(key: persistSessionKey);
    } catch (_) {
      _cached = null;
    }
    // One-time move from the old plain storage.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(persistSessionKey);
    if (legacy != null) {
      if (_cached == null) {
        try {
          await _secure.write(key: persistSessionKey, value: legacy);
          _cached = legacy;
        } catch (_) {
          // Keystore unavailable: keep the old copy so the user stays signed in.
          _cached = legacy;
          return;
        }
      }
      await prefs.remove(persistSessionKey);
    }
  }

  @override
  Future<bool> hasAccessToken() async => _cached != null;

  @override
  Future<String?> accessToken() async => _cached;

  @override
  Future<void> removePersistedSession() async {
    _cached = null;
    try {
      await _secure.delete(key: persistSessionKey);
    } catch (_) {}
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    _cached = persistSessionString;
    try {
      await _secure.write(key: persistSessionKey, value: persistSessionString);
    } catch (e) {
      debugPrint('secure session write failed: $e');
    }
  }
}
