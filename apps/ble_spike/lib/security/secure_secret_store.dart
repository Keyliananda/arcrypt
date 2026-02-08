import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../chat/chat_ids.dart';

const String kSecureStorageDevicePrivX25519Key =
    'prsm_device_static_priv_x25519_v1';
const String kSecureStorageDevicePubX25519Key =
    'prsm_device_static_pub_x25519_v1';

class SecureSecretStore {
  SecureSecretStore({FlutterSecureStorage? storage, AesGcm? aead})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          ),
      _aead = aead ?? AesGcm.with256bits();

  static final SecureSecretStore instance = SecureSecretStore();

  static const String _magic = 'PRSM';
  static const int _blobVersion = 1;
  static const String _kekStorageKey = 'prsm_local_secrets_kek_v1';

  final FlutterSecureStorage _storage;
  final AesGcm _aead;

  SecretKey? _cachedKek;

  bool looksLikeEncryptedSecret(Uint8List bytes) {
    if (bytes.length < 4 + 1 + 12 + 16) {
      return false;
    }
    final magicBytes = ascii.encode(_magic);
    for (var i = 0; i < magicBytes.length; i++) {
      if (bytes[i] != magicBytes[i]) return false;
    }
    return bytes[4] == _blobVersion;
  }

  Future<SimpleKeyPairData?> readDeviceStaticKeyPairX25519() async {
    final privB64 = await _storage.read(key: kSecureStorageDevicePrivX25519Key);
    final pubB64 = await _storage.read(key: kSecureStorageDevicePubX25519Key);
    if (privB64 == null || pubB64 == null) return null;

    final priv = _decodeBase64OrNull(privB64);
    final pub = _decodeBase64OrNull(pubB64);
    if (priv == null || pub == null) return null;
    if (priv.length != 32 || pub.length != 32) return null;

    return SimpleKeyPairData(
      Uint8List.fromList(priv),
      publicKey: SimplePublicKey(
        Uint8List.fromList(pub),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
  }

  Future<void> writeDeviceStaticKeyPairX25519({
    required Uint8List privateKey32,
    required Uint8List publicKey32,
  }) async {
    if (privateKey32.length != 32) {
      throw ArgumentError('privateKey32 must be 32 bytes');
    }
    if (publicKey32.length != 32) {
      throw ArgumentError('publicKey32 must be 32 bytes');
    }
    await _storage.write(
      key: kSecureStorageDevicePrivX25519Key,
      value: base64Encode(privateKey32),
    );
    await _storage.write(
      key: kSecureStorageDevicePubX25519Key,
      value: base64Encode(publicKey32),
    );
  }

  Future<Uint8List> encryptLocalSecret(Uint8List plaintext) async {
    final kek = await _ensureKek();
    final nonce = randomBytes(12);
    final secretBox = await _aead.encrypt(
      plaintext,
      secretKey: kek,
      nonce: nonce,
    );
    final mac = Uint8List.fromList(secretBox.mac.bytes);
    final cipherText = Uint8List.fromList(secretBox.cipherText);
    final magicBytes = ascii.encode(_magic);

    final out = Uint8List(
      magicBytes.length + 1 + nonce.length + cipherText.length + mac.length,
    );
    out.setRange(0, magicBytes.length, magicBytes);
    out[magicBytes.length] = _blobVersion;
    out.setRange(
      magicBytes.length + 1,
      magicBytes.length + 1 + nonce.length,
      nonce,
    );
    out.setRange(
      magicBytes.length + 1 + nonce.length,
      magicBytes.length + 1 + nonce.length + cipherText.length,
      cipherText,
    );
    out.setRange(
      magicBytes.length + 1 + nonce.length + cipherText.length,
      out.length,
      mac,
    );
    return out;
  }

  Future<Uint8List> decryptLocalSecretOrLegacy(Uint8List storedBytes) async {
    if (!looksLikeEncryptedSecret(storedBytes)) {
      return Uint8List.fromList(storedBytes);
    }

    final kek = await _ensureKek();
    const headerLen = 4 + 1;
    final nonceStart = headerLen;
    final nonceEnd = nonceStart + 12;
    final macStart = storedBytes.length - 16;
    if (macStart <= nonceEnd) {
      throw const FormatException('encrypted secret malformed');
    }

    final nonce = storedBytes.sublist(nonceStart, nonceEnd);
    final cipherText = storedBytes.sublist(nonceEnd, macStart);
    final macBytes = storedBytes.sublist(macStart);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
    final plain = await _aead.decrypt(secretBox, secretKey: kek);
    return Uint8List.fromList(plain);
  }

  Future<SecretKey> _ensureKek() async {
    final cached = _cachedKek;
    if (cached != null) return cached;

    final existing = await _storage.read(key: _kekStorageKey);
    if (existing != null) {
      final bytes = _decodeBase64OrNull(existing);
      if (bytes != null && bytes.length == 32) {
        final key = SecretKey(Uint8List.fromList(bytes));
        _cachedKek = key;
        return key;
      }
    }

    final generated = randomBytes(32);
    await _storage.write(key: _kekStorageKey, value: base64Encode(generated));
    final key = SecretKey(Uint8List.fromList(generated));
    _cachedKek = key;
    return key;
  }

  Uint8List? _decodeBase64OrNull(String value) {
    try {
      return Uint8List.fromList(base64Decode(value));
    } on FormatException {
      return null;
    }
  }
}
