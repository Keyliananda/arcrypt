import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../chat/chat_models.dart';

abstract class PairingStorage {
  Future<SimpleKeyPair> ensureDeviceStaticKeyPairX25519();

  Future<Contact> upsertTrustedContactFromStaticPubkey({
    required Uint8List peerStaticPubkeyX25519,
    String? nickname,
    int? nowMs,
  });

  Future<Contact?> findTrustedContactByStaticPubkeyX25519({
    required Uint8List peerStaticPubkeyX25519,
  });

  Future<Contact?> findContactById(String contactId);

  Future<KeyMaterial?> findKeyById(String keyId);

  Future<KeyMaterial?> findCurrentKeyForContact(String contactId);

  Future<KeyMaterial?> findPendingKeyForContact(String contactId);

  Future<KeyMaterial> preparePendingKeyForContact({
    required String contactId,
    required String keyId,
    required Uint8List masterKey32,
    required int nowMs,
  });

  Future<void> commitPendingKeyForContact({
    required String contactId,
    required String keyId,
    required int nowMs,
  });

  Future<void> markContactSeen({required String contactId, required int nowMs});
}
