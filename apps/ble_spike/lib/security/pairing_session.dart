import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../chat/chat.dart';
import 'noise_xx.dart';
import 'pairing_storage.dart';
import 'secure_channel.dart';

const int kSecMagic = 0xF0;

const int kSecMsgHs1 = 1;
const int kSecMsgHs2 = 2;
const int kSecMsgHs3 = 3;
const int kSecMsgSasOk = 4;
const int kSecMsgMasterKey = 5;
const int kSecMsgMasterKeyAck = 6;
const int kSecMsgMasterKeyCommit = 7;
const int kSecMsgUseCurrentKey = 8;

const int _keyAckModeReuse = 1;
const int _keyAckModeRotatePrepared = 2;

enum PairingStage {
  idle,
  handshaking,
  sasReady,
  waitingPeerSas,
  waitingMasterKey,
  waitingMasterKeyAck,
  waitingMasterKeyCommit,
  established,
  failed,
}

class PairingSession {
  PairingSession({
    required this.role,
    required Future<void> Function(Uint8List bytes) send,
    required void Function() onUpdate,
    PairingStorage? storage,
    Uint8List? expectedPeerStaticPubkeyX25519,
    bool requireExpectedPeer = false,
    bool autoConfirmSasIfTrusted = true,
    Duration refreshWindow = const Duration(minutes: 10),
    Duration minStableForRefresh = const Duration(seconds: 15),
    int Function()? nowMs,
  }) : _send = send,
       _onUpdate = onUpdate,
       _storage = storage ?? ChatStorage.instance,
       _expectedPeerStaticPubkeyX25519 = expectedPeerStaticPubkeyX25519 == null
           ? null
           : Uint8List.fromList(expectedPeerStaticPubkeyX25519),
       _requireExpectedPeer = requireExpectedPeer,
       _autoConfirmSasIfTrusted = autoConfirmSasIfTrusted,
       _refreshWindow = refreshWindow,
       _minStableForRefresh = minStableForRefresh,
       _nowMs = nowMs ?? _defaultNowMs,
       _connectedAtMs = (nowMs ?? _defaultNowMs)();

  final ChatRole role;
  final Future<void> Function(Uint8List bytes) _send;
  final void Function() _onUpdate;
  final PairingStorage _storage;
  final Uint8List? _expectedPeerStaticPubkeyX25519;
  final bool _requireExpectedPeer;
  final bool _autoConfirmSasIfTrusted;
  final Duration _refreshWindow;
  final Duration _minStableForRefresh;
  final int Function() _nowMs;
  final int _connectedAtMs;

  PairingStage stage = PairingStage.idle;
  String? error;

  String? sas;
  bool localSasConfirmed = false;
  bool peerSasConfirmed = false;

  Uint8List? sessionId4;
  Uint8List? masterKey32;
  Uint8List? peerStaticPubkeyX25519;
  String? contactId;
  String? keyId;
  bool trustedReconnect = false;

  SecureChannel? _channel;
  NoiseXXInitiator? _i;
  NoiseXXResponder? _r;
  bool _initiatorKeyNegotiationStarted = false;
  String? _preparedRotationKeyId;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  Future<void> startIfInitiator() async {
    if (role != ChatRole.initiator) return;
    if (stage != PairingStage.idle) return;

    try {
      stage = PairingStage.handshaking;
      _onUpdate();

      final staticKeys = await _storage.ensureDeviceStaticKeyPairX25519();
      _i = NoiseXXInitiator(staticKeyPair: staticKeys);
      final msg1 = await _i!.startMessage1();
      await _send(_wrap(kSecMsgHs1, msg1));
    } catch (e) {
      _fail('handshake init failed: $e');
    }
  }

  Future<bool> handleIncoming(Uint8List message) async {
    if (message.isEmpty || message[0] != kSecMagic) return false;
    if (message.length < 2) {
      _fail('security envelope too short');
      return true;
    }

    final type = message[1];
    final payload = Uint8List.fromList(message.sublist(2));

    try {
      switch (type) {
        case kSecMsgHs1:
          await _onHs1(payload);
          return true;
        case kSecMsgHs2:
          await _onHs2(payload);
          return true;
        case kSecMsgHs3:
          await _onHs3(payload);
          return true;
        case kSecMsgSasOk:
          peerSasConfirmed = true;
          _maybeProceedAfterSas();
          _onUpdate();
          return true;
        case kSecMsgMasterKey:
          await _onMasterKey(payload);
          return true;
        case kSecMsgMasterKeyAck:
          await _onMasterKeyAck(payload);
          return true;
        case kSecMsgMasterKeyCommit:
          await _onMasterKeyCommit(payload);
          return true;
        case kSecMsgUseCurrentKey:
          await _onUseCurrentKey(payload);
          return true;
        default:
          _fail('unknown security message type: $type');
          return true;
      }
    } catch (e) {
      _fail('security message handling failed: $e');
      return true;
    }
  }

  Future<void> confirmSas() async {
    if (stage != PairingStage.sasReady &&
        stage != PairingStage.waitingPeerSas) {
      return;
    }
    if (localSasConfirmed) return;
    localSasConfirmed = true;
    await _send(_wrap(kSecMsgSasOk, Uint8List(0)));
    _maybeProceedAfterSas();
    _onUpdate();
  }

  void reset() {
    stage = PairingStage.idle;
    error = null;
    sas = null;
    localSasConfirmed = false;
    peerSasConfirmed = false;
    sessionId4 = null;
    masterKey32 = null;
    peerStaticPubkeyX25519 = null;
    contactId = null;
    keyId = null;
    trustedReconnect = false;
    _channel = null;
    _i = null;
    _r = null;
    _initiatorKeyNegotiationStarted = false;
    _preparedRotationKeyId = null;
    _onUpdate();
  }

  Uint8List _wrap(int type, Uint8List payload) {
    final out = Uint8List(2 + payload.length);
    out[0] = kSecMagic;
    out[1] = type & 0xFF;
    if (payload.isNotEmpty) {
      out.setRange(2, out.length, payload);
    }
    return out;
  }

  Future<void> _onHs1(Uint8List payload) async {
    if (role != ChatRole.responder) {
      _fail('received hs1 but we are initiator');
      return;
    }
    if (stage != PairingStage.idle) {
      if (stage == PairingStage.handshaking) return;
      _fail('received hs1 in unexpected stage: $stage');
      return;
    }

    stage = PairingStage.handshaking;
    _onUpdate();

    final staticKeys = await _storage.ensureDeviceStaticKeyPairX25519();
    _r = NoiseXXResponder(staticKeyPair: staticKeys);
    final msg2 = await _r!.readMessage1AndWriteMessage2(payload);
    await _send(_wrap(kSecMsgHs2, msg2));
  }

  Future<void> _onHs2(Uint8List payload) async {
    if (role != ChatRole.initiator) {
      _fail('received hs2 but we are responder');
      return;
    }
    if (_i == null) {
      _fail('received hs2 without initiator state');
      return;
    }
    if (stage != PairingStage.handshaking) {
      _fail('received hs2 in unexpected stage: $stage');
      return;
    }

    final msg3 = await _i!.readMessage2AndWriteMessage3(payload);
    await _send(_wrap(kSecMsgHs3, msg3));

    final result = await _i!.finish();
    await _finalizeHandshake(result, isInitiator: true);
  }

  Future<void> _onHs3(Uint8List payload) async {
    if (role != ChatRole.responder) {
      _fail('received hs3 but we are initiator');
      return;
    }
    if (_r == null) {
      _fail('received hs3 without responder state');
      return;
    }
    if (stage != PairingStage.handshaking) {
      _fail('received hs3 in unexpected stage: $stage');
      return;
    }

    await _r!.readMessage3(payload);
    final result = await _r!.finish();
    await _finalizeHandshake(result, isInitiator: false);
  }

  Future<void> _finalizeHandshake(
    NoiseXXHandshakeResult result, {
    required bool isInitiator,
  }) async {
    sessionId4 = sessionId4FromHandshakeHash(result.handshakeHash);
    sas = sasString6FromHandshakeHash(result.handshakeHash);
    peerStaticPubkeyX25519 = Uint8List.fromList(result.peerStaticPublicKey);

    if (peerStaticPubkeyX25519!.length != 32) {
      _fail('peer static pubkey length invalid');
      return;
    }

    final expected = _expectedPeerStaticPubkeyX25519;
    if (expected != null && expected.length != 32) {
      _fail('expected peer static pubkey must be 32 bytes');
      return;
    }

    final known = await _storage.findTrustedContactByStaticPubkeyX25519(
      peerStaticPubkeyX25519: peerStaticPubkeyX25519!,
    );
    if (known != null) {
      contactId = known.contactId;
    }

    if (expected != null) {
      if (!_bytesEqual(expected, peerStaticPubkeyX25519!)) {
        _fail('pinned peer key mismatch (refusing silent downgrade)');
        return;
      }
      trustedReconnect = true;
    } else {
      trustedReconnect = known != null;
    }

    if (_requireExpectedPeer && !trustedReconnect) {
      _fail('expected trusted peer not found (refusing silent downgrade)');
      return;
    }

    final txKey = isInitiator
        ? result.initiatorToResponderKey
        : result.responderToInitiatorKey;
    final rxKey = isInitiator
        ? result.responderToInitiatorKey
        : result.initiatorToResponderKey;
    _channel = SecureChannel(
      sessionId4: sessionId4!,
      txKey: txKey,
      rxKey: rxKey,
    );

    stage = PairingStage.sasReady;
    _onUpdate();

    if (trustedReconnect && _autoConfirmSasIfTrusted && !localSasConfirmed) {
      unawaited(confirmSas());
    }
  }

  void _maybeProceedAfterSas() {
    if (stage == PairingStage.failed || stage == PairingStage.established)
      return;
    if (sas == null || sessionId4 == null || _channel == null) return;

    if (!localSasConfirmed || !peerSasConfirmed) {
      stage = PairingStage.waitingPeerSas;
      return;
    }

    if (role == ChatRole.initiator) {
      if (!_initiatorKeyNegotiationStarted) {
        _initiatorKeyNegotiationStarted = true;
        unawaited(_runInitiatorKeyNegotiation());
      }
      return;
    }

    stage = PairingStage.waitingMasterKey;
  }

  Future<void> _runInitiatorKeyNegotiation() async {
    final channel = _channel;
    final peerKey = peerStaticPubkeyX25519;
    if (channel == null || peerKey == null) {
      _fail('cannot negotiate key: channel or peer key missing');
      return;
    }

    final now = _nowMs();
    final existing = contactId == null
        ? null
        : await _storage.findContactById(contactId!);
    final hasExistingCurrentKey =
        existing != null && existing.currentKeyId.isNotEmpty;
    final currentKey = hasExistingCurrentKey
        ? await _storage.findKeyById(existing!.currentKeyId)
        : null;

    final shouldRotateInitial = !trustedReconnect || currentKey == null;
    final reconnectRefreshDue =
        trustedReconnect &&
        existing != null &&
        currentKey != null &&
        (now - existing.lastSeenAtMs >= _refreshWindow.inMilliseconds) &&
        (now - _connectedAtMs >= _minStableForRefresh.inMilliseconds);
    final shouldRotate = shouldRotateInitial || reconnectRefreshDue;

    if (!shouldRotate && currentKey != null) {
      masterKey32 = Uint8List.fromList(currentKey.masterKey);
      keyId = currentKey.keyId;
      contactId = existing!.contactId;

      final payload = _encodeKeyIdPayload(currentKey.keyId);
      final enc = await channel.encrypt(payload);
      stage = PairingStage.waitingMasterKeyAck;
      _onUpdate();
      await _send(_wrap(kSecMsgUseCurrentKey, enc));
      return;
    }

    final contact = await _storage.upsertTrustedContactFromStaticPubkey(
      peerStaticPubkeyX25519: peerKey,
      nowMs: now,
    );
    contactId = contact.contactId;

    final nextMasterKey = randomBytes(32);
    final nextKeyId = generateId();
    await _storage.preparePendingKeyForContact(
      contactId: contact.contactId,
      keyId: nextKeyId,
      masterKey32: nextMasterKey,
      nowMs: now,
    );
    _preparedRotationKeyId = nextKeyId;

    final payload = _encodeMasterKeyPayload(
      keyId: nextKeyId,
      masterKey32: nextMasterKey,
    );
    final enc = await channel.encrypt(payload);
    stage = PairingStage.waitingMasterKeyAck;
    _onUpdate();
    await _send(_wrap(kSecMsgMasterKey, enc));
  }

  Future<void> _onMasterKey(Uint8List payload) async {
    if (role != ChatRole.responder) {
      _fail('received master key but we are initiator');
      return;
    }
    final channel = _channel;
    final peerKey = peerStaticPubkeyX25519;
    if (channel == null || peerKey == null) {
      _fail('received master key before channel/peer key ready');
      return;
    }

    final now = _nowMs();
    final plain = await channel.decrypt(payload);
    final decoded = _decodeMasterKeyPayload(plain);

    final contact = await _storage.upsertTrustedContactFromStaticPubkey(
      peerStaticPubkeyX25519: peerKey,
      nowMs: now,
    );
    contactId = contact.contactId;

    await _storage.preparePendingKeyForContact(
      contactId: contact.contactId,
      keyId: decoded.keyId,
      masterKey32: decoded.masterKey32,
      nowMs: now,
    );

    final ackPayload = _encodeKeyAckPayload(
      mode: _keyAckModeRotatePrepared,
      keyId: decoded.keyId,
    );
    final ack = await channel.encrypt(ackPayload);
    await _send(_wrap(kSecMsgMasterKeyAck, ack));

    stage = PairingStage.waitingMasterKeyCommit;
    _onUpdate();
  }

  Future<void> _onUseCurrentKey(Uint8List payload) async {
    if (role != ChatRole.responder) {
      _fail('received use-current-key but we are initiator');
      return;
    }
    final channel = _channel;
    final peerKey = peerStaticPubkeyX25519;
    if (channel == null || peerKey == null) {
      _fail('received use-current-key before channel/peer key ready');
      return;
    }

    final plain = await channel.decrypt(payload);
    final requestedKeyId = _decodeKeyIdPayload(plain);
    final now = _nowMs();

    final contact = await _storage.upsertTrustedContactFromStaticPubkey(
      peerStaticPubkeyX25519: peerKey,
      nowMs: now,
    );
    contactId = contact.contactId;

    final existing = await _storage.findKeyById(requestedKeyId);
    if (existing == null) {
      _fail('requested current key not found: $requestedKeyId');
      return;
    }
    if (existing.contactId != contact.contactId) {
      _fail('requested key does not belong to contact');
      return;
    }

    masterKey32 = Uint8List.fromList(existing.masterKey);
    keyId = existing.keyId;
    await _storage.markContactSeen(contactId: contact.contactId, nowMs: now);

    final ackPayload = _encodeKeyAckPayload(
      mode: _keyAckModeReuse,
      keyId: existing.keyId,
    );
    final ack = await channel.encrypt(ackPayload);
    await _send(_wrap(kSecMsgMasterKeyAck, ack));

    stage = PairingStage.established;
    _onUpdate();
  }

  Future<void> _onMasterKeyAck(Uint8List payload) async {
    if (role != ChatRole.initiator) {
      _fail('received master key ack but we are responder');
      return;
    }
    final channel = _channel;
    final resolvedContactId = contactId;
    if (channel == null || peerStaticPubkeyX25519 == null) {
      _fail('received ack before channel/peer key ready');
      return;
    }
    if (stage != PairingStage.waitingMasterKeyAck) {
      _fail('received ack in unexpected stage: $stage');
      return;
    }
    if (resolvedContactId == null) {
      _fail('received ack without contact');
      return;
    }

    final plain = await channel.decrypt(payload);
    final ack = _decodeKeyAckPayload(plain);
    final now = _nowMs();

    if (ack.mode == _keyAckModeReuse) {
      final existing = await _storage.findKeyById(ack.keyId);
      if (existing == null) {
        _fail('ack references unknown key: ${ack.keyId}');
        return;
      }
      if (existing.contactId != resolvedContactId) {
        _fail('ack key belongs to unexpected contact');
        return;
      }
      masterKey32 = Uint8List.fromList(existing.masterKey);
      keyId = existing.keyId;
      await _storage.markContactSeen(contactId: resolvedContactId, nowMs: now);
      stage = PairingStage.established;
      _onUpdate();
      return;
    }

    if (ack.mode != _keyAckModeRotatePrepared) {
      _fail('ack has unknown mode: ${ack.mode}');
      return;
    }

    if (_preparedRotationKeyId == null || _preparedRotationKeyId != ack.keyId) {
      _fail('ack key mismatch for prepared rotation');
      return;
    }

    await _storage.commitPendingKeyForContact(
      contactId: resolvedContactId,
      keyId: ack.keyId,
      nowMs: now,
    );
    final committed = await _storage.findKeyById(ack.keyId);
    if (committed == null) {
      _fail('committed key not found: ${ack.keyId}');
      return;
    }
    if (committed.contactId != resolvedContactId) {
      _fail('committed key belongs to unexpected contact');
      return;
    }
    masterKey32 = Uint8List.fromList(committed.masterKey);
    keyId = committed.keyId;

    final commitPayload = _encodeKeyIdPayload(ack.keyId);
    final commit = await channel.encrypt(commitPayload);
    await _send(_wrap(kSecMsgMasterKeyCommit, commit));

    stage = PairingStage.established;
    _onUpdate();
  }

  Future<void> _onMasterKeyCommit(Uint8List payload) async {
    if (role != ChatRole.responder) {
      _fail('received master key commit but we are initiator');
      return;
    }
    final channel = _channel;
    final resolvedContactId = contactId;
    if (channel == null || resolvedContactId == null) {
      _fail('received commit before channel/contact ready');
      return;
    }
    if (stage != PairingStage.waitingMasterKeyCommit) {
      _fail('received commit in unexpected stage: $stage');
      return;
    }

    final plain = await channel.decrypt(payload);
    final committedKeyId = _decodeKeyIdPayload(plain);
    final now = _nowMs();

    await _storage.commitPendingKeyForContact(
      contactId: resolvedContactId,
      keyId: committedKeyId,
      nowMs: now,
    );
    final committed = await _storage.findKeyById(committedKeyId);
    if (committed == null) {
      _fail('committed key not found: $committedKeyId');
      return;
    }
    if (committed.contactId != resolvedContactId) {
      _fail('committed key belongs to unexpected contact');
      return;
    }
    masterKey32 = Uint8List.fromList(committed.masterKey);
    keyId = committed.keyId;

    stage = PairingStage.established;
    _onUpdate();
  }

  Uint8List _encodeMasterKeyPayload({
    required String keyId,
    required Uint8List masterKey32,
  }) {
    if (masterKey32.length != 32) {
      throw ArgumentError('masterKey32 must be 32 bytes');
    }
    final keyIdBytes = utf8.encode(keyId);
    if (keyIdBytes.isEmpty || keyIdBytes.length > 255) {
      throw ArgumentError('keyId length must be in 1..255');
    }
    final out = Uint8List(2 + keyIdBytes.length + masterKey32.length);
    out[0] = 1;
    out[1] = keyIdBytes.length;
    out.setRange(2, 2 + keyIdBytes.length, keyIdBytes);
    out.setRange(2 + keyIdBytes.length, out.length, masterKey32);
    return out;
  }

  _MasterKeyPayload _decodeMasterKeyPayload(Uint8List payload) {
    if (payload.length < 2 + 32) {
      throw const FormatException('master key payload too short');
    }
    if (payload[0] != 1) {
      throw const FormatException('master key payload version unsupported');
    }
    final keyIdLen = payload[1];
    final keyIdEnd = 2 + keyIdLen;
    if (keyIdLen == 0 || keyIdEnd + 32 != payload.length) {
      throw const FormatException('master key payload malformed');
    }
    final keyId = utf8.decode(payload.sublist(2, keyIdEnd));
    final keyBytes = Uint8List.fromList(payload.sublist(keyIdEnd));
    if (keyBytes.length != 32) {
      throw const FormatException('master key bytes length invalid');
    }
    return _MasterKeyPayload(keyId: keyId, masterKey32: keyBytes);
  }

  Uint8List _encodeKeyIdPayload(String keyId) {
    final keyIdBytes = utf8.encode(keyId);
    if (keyIdBytes.isEmpty || keyIdBytes.length > 255) {
      throw ArgumentError('keyId length must be in 1..255');
    }
    final out = Uint8List(2 + keyIdBytes.length);
    out[0] = 1;
    out[1] = keyIdBytes.length;
    out.setRange(2, out.length, keyIdBytes);
    return out;
  }

  String _decodeKeyIdPayload(Uint8List payload) {
    if (payload.length < 2) {
      throw const FormatException('key id payload too short');
    }
    if (payload[0] != 1) {
      throw const FormatException('key id payload version unsupported');
    }
    final keyIdLen = payload[1];
    if (keyIdLen == 0 || payload.length != 2 + keyIdLen) {
      throw const FormatException('key id payload malformed');
    }
    return utf8.decode(payload.sublist(2));
  }

  Uint8List _encodeKeyAckPayload({required int mode, required String keyId}) {
    final keyIdBytes = utf8.encode(keyId);
    if (keyIdBytes.isEmpty || keyIdBytes.length > 255) {
      throw ArgumentError('keyId length must be in 1..255');
    }
    final out = Uint8List(3 + keyIdBytes.length);
    out[0] = 1;
    out[1] = mode & 0xFF;
    out[2] = keyIdBytes.length;
    out.setRange(3, out.length, keyIdBytes);
    return out;
  }

  _KeyAckPayload _decodeKeyAckPayload(Uint8List payload) {
    if (payload.length < 3) {
      throw const FormatException('key ack payload too short');
    }
    if (payload[0] != 1) {
      throw const FormatException('key ack payload version unsupported');
    }
    final mode = payload[1];
    final keyIdLen = payload[2];
    if (keyIdLen == 0 || payload.length != 3 + keyIdLen) {
      throw const FormatException('key ack payload malformed');
    }
    final keyId = utf8.decode(payload.sublist(3));
    return _KeyAckPayload(mode: mode, keyId: keyId);
  }

  void _fail(String msg) {
    stage = PairingStage.failed;
    error = msg;
    _onUpdate();
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _MasterKeyPayload {
  _MasterKeyPayload({required this.keyId, required this.masterKey32});

  final String keyId;
  final Uint8List masterKey32;
}

class _KeyAckPayload {
  _KeyAckPayload({required this.mode, required this.keyId});

  final int mode;
  final String keyId;
}
