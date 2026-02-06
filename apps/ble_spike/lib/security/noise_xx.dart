import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const String kNoiseXX25519ChaChaPolySha256 = 'Noise_XX_25519_ChaChaPoly_SHA256';
const int kNoiseDhLen = 32;
const int kNoiseTagLen = 16;

class NoiseHandshakeException implements Exception {
  NoiseHandshakeException(this.message);

  final String message;

  @override
  String toString() => 'NoiseHandshakeException: $message';
}

Uint8List sasDigits6FromHandshakeHash(Uint8List handshakeHash) {
  if (handshakeHash.length < 4) {
    throw NoiseHandshakeException('handshakeHash must be at least 4 bytes');
  }
  final v = (handshakeHash[0] << 24) |
      (handshakeHash[1] << 16) |
      (handshakeHash[2] << 8) |
      (handshakeHash[3]);
  final code = (v % 1000000).toString().padLeft(6, '0');
  return Uint8List.fromList(code.codeUnits);
}

String sasString6FromHandshakeHash(Uint8List handshakeHash) {
  final bytes = sasDigits6FromHandshakeHash(handshakeHash);
  return String.fromCharCodes(bytes);
}

Uint8List sessionId4FromHandshakeHash(Uint8List handshakeHash) {
  if (handshakeHash.length < 4) {
    throw NoiseHandshakeException('handshakeHash must be at least 4 bytes');
  }
  return Uint8List.fromList(handshakeHash.sublist(0, 4));
}

class NoiseXXHandshakeResult {
  NoiseXXHandshakeResult({
    required this.handshakeHash,
    required this.peerStaticPublicKey,
    required this.initiatorToResponderKey,
    required this.responderToInitiatorKey,
  });

  final Uint8List handshakeHash;
  final Uint8List peerStaticPublicKey;
  final SecretKey initiatorToResponderKey;
  final SecretKey responderToInitiatorKey;
}

class NoiseXXInitiator {
  NoiseXXInitiator({
    required SimpleKeyPair staticKeyPair,
  }) : _staticKeyPair = staticKeyPair;

  final SimpleKeyPair _staticKeyPair;

  final _SymmetricState _s = _SymmetricState();
  final X25519 _dh = X25519();

  SimpleKeyPair? _e;
  SimplePublicKey? _re;
  Uint8List? _rs;

  bool _started = false;
  bool _finished = false;

  Future<Uint8List> startMessage1() async {
    if (_started) {
      throw NoiseHandshakeException('handshake already started');
    }
    _started = true;

    await _s.initialize();

    _e = await _dh.newKeyPair();
    final ePub = await _e!.extractPublicKey();
    if (ePub.bytes.length != kNoiseDhLen) {
      throw NoiseHandshakeException('unexpected ephemeral pubkey length');
    }
    await _s.mixHash(Uint8List.fromList(ePub.bytes));

    return Uint8List.fromList(ePub.bytes);
  }

  Future<Uint8List> readMessage2AndWriteMessage3(Uint8List message2) async {
    if (!_started) {
      throw NoiseHandshakeException('handshake not started');
    }
    if (_finished) {
      throw NoiseHandshakeException('handshake already finished');
    }
    if (_e == null) {
      throw NoiseHandshakeException('missing ephemeral key');
    }
    if (message2.length < kNoiseDhLen + kNoiseDhLen + kNoiseTagLen) {
      throw NoiseHandshakeException('message2 too short');
    }

    final reBytes = message2.sublist(0, kNoiseDhLen);
    _re = SimplePublicKey(reBytes, type: KeyPairType.x25519);
    await _s.mixHash(Uint8List.fromList(reBytes));

    // ee
    final ee = await _dh.sharedSecretKey(
      keyPair: _e!,
      remotePublicKey: _re!,
    );
    await _s.mixKey(Uint8List.fromList(await ee.extractBytes()));

    // s (encrypted static pubkey of responder)
    final encS = message2.sublist(kNoiseDhLen, kNoiseDhLen + kNoiseDhLen + kNoiseTagLen);
    final rsBytes = await _s.decryptAndHash(encS);
    if (rsBytes.length != kNoiseDhLen) {
      throw NoiseHandshakeException('unexpected responder static pubkey length');
    }
    _rs = Uint8List.fromList(rsBytes);

    // es
    final rsPub = SimplePublicKey(_rs!, type: KeyPairType.x25519);
    final es = await _dh.sharedSecretKey(
      keyPair: _e!,
      remotePublicKey: rsPub,
    );
    await _s.mixKey(Uint8List.fromList(await es.extractBytes()));

    // -> s, se
    final sPub = await _staticKeyPair.extractPublicKey();
    final encSi = await _s.encryptAndHash(Uint8List.fromList(sPub.bytes));

    final se = await _dh.sharedSecretKey(
      keyPair: _staticKeyPair,
      remotePublicKey: _re!,
    );
    await _s.mixKey(Uint8List.fromList(await se.extractBytes()));

    _finished = true;

    return encSi;
  }

  Future<NoiseXXHandshakeResult> finish() async {
    if (!_finished) {
      throw NoiseHandshakeException('handshake not finished');
    }
    if (_rs == null) {
      throw NoiseHandshakeException('missing responder static pubkey');
    }
    final split = await _s.split();
    return NoiseXXHandshakeResult(
      handshakeHash: Uint8List.fromList(_s.h),
      peerStaticPublicKey: Uint8List.fromList(_rs!),
      initiatorToResponderKey: split.k1,
      responderToInitiatorKey: split.k2,
    );
  }
}

class NoiseXXResponder {
  NoiseXXResponder({
    required SimpleKeyPair staticKeyPair,
  }) : _staticKeyPair = staticKeyPair;

  final SimpleKeyPair _staticKeyPair;

  final _SymmetricState _s = _SymmetricState();
  final X25519 _dh = X25519();

  SimpleKeyPair? _e;
  SimplePublicKey? _re;
  Uint8List? _rs;

  bool _started = false;
  bool _finished = false;

  Future<Uint8List> readMessage1AndWriteMessage2(Uint8List message1) async {
    if (_started) {
      throw NoiseHandshakeException('handshake already started');
    }
    _started = true;

    if (message1.length != kNoiseDhLen) {
      throw NoiseHandshakeException('message1 must be 32 bytes');
    }

    await _s.initialize();

    _re = SimplePublicKey(message1, type: KeyPairType.x25519);
    await _s.mixHash(message1);

    _e = await _dh.newKeyPair();
    final ePub = await _e!.extractPublicKey();
    if (ePub.bytes.length != kNoiseDhLen) {
      throw NoiseHandshakeException('unexpected ephemeral pubkey length');
    }
    await _s.mixHash(Uint8List.fromList(ePub.bytes));

    // ee
    final ee = await _dh.sharedSecretKey(
      keyPair: _e!,
      remotePublicKey: _re!,
    );
    await _s.mixKey(Uint8List.fromList(await ee.extractBytes()));

    // s (send encrypted static pubkey of responder)
    final sPub = await _staticKeyPair.extractPublicKey();
    final encSr = await _s.encryptAndHash(Uint8List.fromList(sPub.bytes));

    // es
    final es = await _dh.sharedSecretKey(
      keyPair: _staticKeyPair,
      remotePublicKey: _re!,
    );
    await _s.mixKey(Uint8List.fromList(await es.extractBytes()));

    final out = BytesBuilder(copy: false)
      ..add(ePub.bytes)
      ..add(encSr);
    return out.toBytes();
  }

  Future<void> readMessage3(Uint8List message3) async {
    if (!_started) {
      throw NoiseHandshakeException('handshake not started');
    }
    if (_finished) {
      throw NoiseHandshakeException('handshake already finished');
    }
    if (_e == null || _re == null) {
      throw NoiseHandshakeException('missing ephemeral keys');
    }

    if (message3.length != kNoiseDhLen + kNoiseTagLen) {
      throw NoiseHandshakeException('message3 length invalid');
    }

    final siBytes = await _s.decryptAndHash(message3);
    if (siBytes.length != kNoiseDhLen) {
      throw NoiseHandshakeException('unexpected initiator static pubkey length');
    }
    _rs = Uint8List.fromList(siBytes);

    // se
    final siPub = SimplePublicKey(_rs!, type: KeyPairType.x25519);
    final se = await _dh.sharedSecretKey(
      keyPair: _e!,
      remotePublicKey: siPub,
    );
    await _s.mixKey(Uint8List.fromList(await se.extractBytes()));

    _finished = true;
  }

  Future<NoiseXXHandshakeResult> finish() async {
    if (!_finished) {
      throw NoiseHandshakeException('handshake not finished');
    }
    if (_rs == null) {
      throw NoiseHandshakeException('missing initiator static pubkey');
    }
    final split = await _s.split();
    return NoiseXXHandshakeResult(
      handshakeHash: Uint8List.fromList(_s.h),
      peerStaticPublicKey: Uint8List.fromList(_rs!),
      initiatorToResponderKey: split.k1,
      responderToInitiatorKey: split.k2,
    );
  }
}

class _SplitResult {
  _SplitResult({required this.k1, required this.k2});

  final SecretKey k1;
  final SecretKey k2;
}

class _CipherState {
  _CipherState({required Chacha20 aead}) : _aead = aead;

  final Chacha20 _aead;
  SecretKey? _k;
  int _n = 0;

  bool get hasKey => _k != null;

  void initializeKey(SecretKey key) {
    _k = key;
    _n = 0;
  }

  Uint8List _nonce12For(int n) {
    final nonce = Uint8List(12);
    // first 4 bytes zero
    final data = ByteData.sublistView(nonce, 4);
    data.setUint64(0, n, Endian.little);
    return nonce;
  }

  Future<Uint8List> encrypt({required Uint8List ad, required Uint8List plaintext}) async {
    if (_k == null) {
      return Uint8List.fromList(plaintext);
    }
    final box = await _aead.encrypt(
      plaintext,
      secretKey: _k!,
      nonce: _nonce12For(_n),
      aad: ad,
    );
    _n += 1;
    final out = BytesBuilder(copy: false)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  Future<Uint8List> decrypt({required Uint8List ad, required Uint8List ciphertextAndTag}) async {
    if (_k == null) {
      return Uint8List.fromList(ciphertextAndTag);
    }
    if (ciphertextAndTag.length < kNoiseTagLen) {
      throw NoiseHandshakeException('ciphertext too short');
    }
    final cipherText = ciphertextAndTag.sublist(0, ciphertextAndTag.length - kNoiseTagLen);
    final tag = ciphertextAndTag.sublist(ciphertextAndTag.length - kNoiseTagLen);
    final box = SecretBox(cipherText, nonce: _nonce12For(_n), mac: Mac(tag));
    final plaintext = await _aead.decrypt(box, secretKey: _k!, aad: ad);
    _n += 1;
    return Uint8List.fromList(plaintext);
  }
}

class _SymmetricState {
  Uint8List ck = Uint8List(0);
  Uint8List h = Uint8List(0);
  late final _CipherState _cs;
  late final Sha256 _hash;
  late final Hkdf _hkdf;

  Future<void> initialize() async {
    _hash = Sha256();
    _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
    _cs = _CipherState(aead: Chacha20.poly1305Aead());

    final protoBytes = Uint8List.fromList(kNoiseXX25519ChaChaPolySha256.codeUnits);
    h = Uint8List.fromList(await _hash.hash(protoBytes).then((v) => v.bytes));
    ck = Uint8List.fromList(h);
  }

  Future<void> mixHash(Uint8List data) async {
    final b = BytesBuilder(copy: false)
      ..add(h)
      ..add(data);
    h = Uint8List.fromList((await _hash.hash(b.toBytes())).bytes);
  }

  Future<void> mixKey(Uint8List ikm) async {
    final out = await _hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: ck,
      info: Uint8List(0),
    );
    final okm = await out.extractBytes();
    final ckNew = okm.sublist(0, 32);
    final tempK = okm.sublist(32, 64);
    ck = Uint8List.fromList(ckNew);
    _cs.initializeKey(SecretKey(tempK));
  }

  Future<Uint8List> encryptAndHash(Uint8List plaintext) async {
    final ciphertext = await _cs.encrypt(ad: h, plaintext: plaintext);
    await mixHash(ciphertext);
    return ciphertext;
  }

  Future<Uint8List> decryptAndHash(Uint8List ciphertext) async {
    final plaintext = await _cs.decrypt(ad: h, ciphertextAndTag: ciphertext);
    await mixHash(ciphertext);
    return plaintext;
  }

  Future<_SplitResult> split() async {
    final out = await _hkdf.deriveKey(
      secretKey: SecretKey(Uint8List(0)),
      nonce: ck,
      info: Uint8List(0),
    );
    final okm = await out.extractBytes();
    final k1 = SecretKey(okm.sublist(0, 32));
    final k2 = SecretKey(okm.sublist(32, 64));
    return _SplitResult(k1: k1, k2: k2);
  }
}
