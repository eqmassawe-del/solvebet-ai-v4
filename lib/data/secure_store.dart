import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials live only in Android Keystore-backed secure storage — never in
/// SQLite, logs or exported files.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _s.delete(key: key);
    } else {
      await _s.write(key: key, value: value);
    }
  }
}

/// In-memory store for tests.
class MemorySecretStore implements SecretStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }
}

class SecretKeys {
  static const footballApiKey = 'football_api_key';
  static const aiApiKey = 'ai_api_key';
}
