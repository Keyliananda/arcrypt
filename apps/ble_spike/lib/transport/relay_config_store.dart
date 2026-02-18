import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'relay_runtime_config.dart';

class RelayConfigStore {
  const RelayConfigStore();

  static const String _storageKey = 'prsm_relay_runtime_config_v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<RelayRuntimeConfig?> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return RelayRuntimeConfig.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(RelayRuntimeConfig config) async {
    await _storage.write(key: _storageKey, value: jsonEncode(config.toJson()));
  }

  Future<void> clear() async {
    await _storage.delete(key: _storageKey);
  }
}
