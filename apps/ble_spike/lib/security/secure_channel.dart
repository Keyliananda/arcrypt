import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class SecureChannelException implements Exception {
  SecureChannelException(this.message);

  final String message;

  @override
  String toString() => 'SecureChannelException: $message';
}

class SecureChannel {
  SecureChannel({
    required this.sessionId4,
    required this.txKey,
    required this.rxKey,
    Chacha20? aead,
  }) : _aead = aead ?? Chacha20.poly1305Aead();

  final Uint8List sessionId4;
  final SecretKey txKey;
  final SecretKey rxKey;
  final Chacha20 _aead;

  int _txCounter = 0;
  int _rxLastCounter = -1;

  Uint8List _nonce12(Uint8List sessionId4, int counter) {
    if (sessionId4.length != 4) {
      throw SecureChannelException('sessionId4 must be 4 bytes');
    }
    final nonce = Uint8List(12);
    nonce.setRange(0, 4, sessionId4);
    final data = ByteData.sublistView(nonce, 4);
    data.setUint64(0, counter, Endian.little);
    return nonce;
  }

  Future<Uint8List> encrypt(Uint8List plaintext, {Uint8List? aad}) async {
    final aadBytes = aad ?? Uint8List(0);
    final counter = _txCounter;
    final box = await _aead.encrypt(
      plaintext,
      secretKey: txKey,
      nonce: _nonce12(sessionId4, counter),
      aad: aadBytes,
    );

    final header = ByteData(4)..setUint32(0, counter, Endian.little);
    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    _txCounter += 1;
    return out.toBytes();
  }

  Future<Uint8List> decrypt(Uint8List ciphertext, {Uint8List? aad}) async {
    final aadBytes = aad ?? Uint8List(0);
    if (ciphertext.length < 4 + 16) {
      throw SecureChannelException('ciphertext too short');
    }
    final header = ByteData.sublistView(ciphertext, 0, 4);
    final counter = header.getUint32(0, Endian.little);
    if (counter <= _rxLastCounter) {
      throw SecureChannelException('replay detected');
    }

    final body = ciphertext.sublist(4);
    if (body.length < 16) {
      throw SecureChannelException('ciphertext body too short');
    }
    final ct = body.sublist(0, body.length - 16);
    final tag = body.sublist(body.length - 16);
    final box = SecretBox(
      ct,
      nonce: _nonce12(sessionId4, counter),
      mac: Mac(tag),
    );
    final plaintext = await _aead.decrypt(box, secretKey: rxKey, aad: aadBytes);
    _rxLastCounter = counter;
    return Uint8List.fromList(plaintext);
  }
}
