import 'dart:typed_data';

import 'package:ble_spike/security/secure_secret_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int length, int seed) {
  return Uint8List.fromList(
    List<int>.generate(length, (i) => (i + seed) & 0xFF),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('encrypt/decrypt local secret roundtrip', () async {
    final store = SecureSecretStore(storage: const FlutterSecureStorage());
    final plain = _bytes(32, 17);

    final encrypted = await store.encryptLocalSecret(plain);
    expect(store.looksLikeEncryptedSecret(encrypted), isTrue);

    final decrypted = await store.decryptLocalSecretOrLegacy(encrypted);
    expect(decrypted, plain);
  });

  test('legacy plaintext secret remains readable', () async {
    final store = SecureSecretStore(storage: const FlutterSecureStorage());
    final legacyPlain = _bytes(32, 33);

    final decoded = await store.decryptLocalSecretOrLegacy(legacyPlain);
    expect(decoded, legacyPlain);
  });

  test('device static keypair persists in secure storage', () async {
    final storage = const FlutterSecureStorage();
    final store = SecureSecretStore(storage: storage);
    final priv = _bytes(32, 71);
    final pub = _bytes(32, 91);

    await store.writeDeviceStaticKeyPairX25519(
      privateKey32: priv,
      publicKey32: pub,
    );

    final loaded = await store.readDeviceStaticKeyPairX25519();
    final loadedPriv = await loaded!.extractPrivateKeyBytes();
    final loadedPub = await loaded.extractPublicKey();

    expect(loadedPriv, priv);
    expect(loadedPub.bytes, pub);
  });
}
