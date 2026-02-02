import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

/// Simple APNs service for registering device tokens with the server
class ApnsService {
  static final ApnsService _instance = ApnsService._internal();
  factory ApnsService() => _instance;
  ApnsService._internal();

  String? _deviceToken;
  String? _hmacSecret;
  String? _serverUrl;

  /// Initialize with server URL and HMAC secret
  void configure({
    required String serverUrl,
    required String hmacSecret,
  }) {
    _serverUrl = serverUrl;
    _hmacSecret = hmacSecret;
  }

  /// Register device token with server
  Future<bool> registerToken(String token) async {
    if (_serverUrl == null) {
      debugPrint('APNs: Server URL not configured');
      return false;
    }

    _deviceToken = token;

    try {
      final response = await HttpClient()
          .postUrl(Uri.parse('$_serverUrl/v1/register'))
          .then((request) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'token': token,
          'topic': 'com.arcrypt.bleSpike',
          'env': 'sandbox',
        }));
        return request.close();
      });

      final responseBody = await response.transform(utf8.decoder).join();
      debugPrint('APNs: Register response: $responseBody');

      final data = jsonDecode(responseBody);
      return data['ok'] == true;
    } catch (e) {
      debugPrint('APNs: Register error: $e');
      return false;
    }
  }

  /// Send wake request to another device
  Future<bool> wakeDevice(String targetToken) async {
    if (_serverUrl == null || _hmacSecret == null) {
      debugPrint('APNs: Not initialized');
      return false;
    }

    try {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final proof = _computeHmac(targetToken, ts);

      final response = await HttpClient()
          .postUrl(Uri.parse('$_serverUrl/v1/wake'))
          .then((request) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'token': targetToken,
          'ts': ts,
          'proof': proof,
        }));
        return request.close();
      });

      final responseBody = await response.transform(utf8.decoder).join();
      debugPrint('APNs: Wake response: $responseBody');

      final data = jsonDecode(responseBody);
      return data['ok'] == true;
    } catch (e) {
      debugPrint('APNs: Wake error: $e');
      return false;
    }
  }

  String _computeHmac(String token, int ts) {
    final key = utf8.encode(_hmacSecret!);
    final bytes = utf8.encode('$token:$ts');
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  String? get deviceToken => _deviceToken;
  bool get isConfigured => _serverUrl != null && _hmacSecret != null;
}
