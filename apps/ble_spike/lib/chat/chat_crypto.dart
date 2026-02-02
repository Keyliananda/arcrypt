import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const int kChatVersion = 1;
const int kChatTypeText = 1;
const int kChatHeaderLength = 8;
const int kChatTagLength = 16;
const int kChatMaxCounter = 0xFFFFFFFF;

class ChatHeader {
  const ChatHeader({
    required this.version,
    required this.type,
    required this.counter,
    required this.payloadLength,
  });

  final int version;
  final int type;
  final int counter;
  final int payloadLength;

  Uint8List encode() {
    final bytes = Uint8List(kChatHeaderLength);
    final data = ByteData.sublistView(bytes);
    data.setUint8(0, version);
    data.setUint8(1, type);
    data.setUint32(2, counter, Endian.little);
    data.setUint16(6, payloadLength, Endian.little);
    return bytes;
  }

  static ChatHeader decode(Uint8List bytes) {
    if (bytes.length < kChatHeaderLength) {
      throw const FormatException('chat header too short');
    }
    final data = ByteData.sublistView(bytes);
    return ChatHeader(
      version: data.getUint8(0),
      type: data.getUint8(1),
      counter: data.getUint32(2, Endian.little),
      payloadLength: data.getUint16(6, Endian.little),
    );
  }
}

class ChatCryptoException implements Exception {
  ChatCryptoException(this.message);

  final String message;

  @override
  String toString() => 'ChatCryptoException: $message';
}

class ChatCrypto {
  ChatCrypto({AesGcm? aead}) : _aead = aead ?? AesGcm.with256bits();

  final AesGcm _aead;

  Future<SecretKey> deriveMessageKey({
    required SecretKey masterKey,
    required Uint8List sessionId,
    required int direction,
    required int counter,
  }) async {
    if (sessionId.length != 4) {
      throw ChatCryptoException('sessionId must be 4 bytes');
    }
    final salt = Uint8List(5);
    salt.setRange(0, 4, sessionId);
    salt[4] = direction & 0xFF;

    final infoPrefix = utf8.encode('prsm/msg');
    final info = Uint8List(infoPrefix.length + 4);
    info.setRange(0, infoPrefix.length, infoPrefix);
    final infoData = ByteData.sublistView(info, infoPrefix.length);
    infoData.setUint32(0, counter, Endian.little);

    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );

    return hkdf.deriveKey(
      secretKey: masterKey,
      nonce: salt,
      info: info,
    );
  }

  Uint8List buildNonce(Uint8List sessionId, int counter) {
    if (sessionId.length != 4) {
      throw ChatCryptoException('sessionId must be 4 bytes');
    }
    final nonce = Uint8List(12);
    nonce.setRange(0, 4, sessionId);
    final counterBytes = ByteData(8);
    counterBytes.setUint32(0, counter, Endian.little);
    counterBytes.setUint32(4, 0, Endian.little);
    nonce.setRange(4, 12, counterBytes.buffer.asUint8List());
    return nonce;
  }

  Future<SecretBox> encryptPayload({
    required SecretKey masterKey,
    required Uint8List sessionId,
    required int direction,
    required int counter,
    required Uint8List header,
    required Uint8List plaintext,
  }) async {
    final messageKey = await deriveMessageKey(
      masterKey: masterKey,
      sessionId: sessionId,
      direction: direction,
      counter: counter,
    );
    final nonce = buildNonce(sessionId, counter);
    return _aead.encrypt(
      plaintext,
      secretKey: messageKey,
      nonce: nonce,
      aad: header,
    );
  }

  Future<Uint8List> decryptPayload({
    required SecretKey masterKey,
    required Uint8List sessionId,
    required int direction,
    required int counter,
    required Uint8List header,
    required Uint8List cipherText,
    required Uint8List macBytes,
  }) async {
    final messageKey = await deriveMessageKey(
      masterKey: masterKey,
      sessionId: sessionId,
      direction: direction,
      counter: counter,
    );
    final nonce = buildNonce(sessionId, counter);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
    final decrypted = await _aead.decrypt(
      box,
      secretKey: messageKey,
      aad: header,
    );
    return Uint8List.fromList(decrypted);
  }
}
