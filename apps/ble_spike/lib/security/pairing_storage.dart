import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../chat/chat_models.dart';

abstract class PairingStorage {
  Future<SimpleKeyPair> ensureDeviceStaticKeyPairX25519();

  Future<Contact> upsertTrustedContactFromStaticPubkey({
    required Uint8List peerStaticPubkeyX25519,
    String? nickname,
  });

  Future<Contact?> findTrustedContactByStaticPubkeyX25519({
    required Uint8List peerStaticPubkeyX25519,
  });
}

