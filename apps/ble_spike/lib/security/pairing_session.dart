import 'dart:async';
import 'dart:typed_data';

import '../chat/chat.dart';
import 'noise_xx.dart';
import 'secure_channel.dart';

const int kSecMagic = 0xF0;

const int kSecMsgHs1 = 1;
const int kSecMsgHs2 = 2;
const int kSecMsgHs3 = 3;
const int kSecMsgSasOk = 4;
const int kSecMsgMasterKey = 5;
const int kSecMsgMasterKeyAck = 6;

enum PairingStage {
  idle,
  handshaking,
  sasReady,
  waitingPeerSas,
  waitingMasterKey,
  waitingMasterKeyAck,
  established,
  failed,
}

class PairingSession {
  PairingSession({
    required this.role,
    required Future<void> Function(Uint8List bytes) send,
    required void Function() onUpdate,
    ChatStorage? storage,
  })  : _send = send,
        _onUpdate = onUpdate,
        _storage = storage ?? ChatStorage.instance;

  final ChatRole role;
  final Future<void> Function(Uint8List bytes) _send;
  final void Function() _onUpdate;
  final ChatStorage _storage;

  PairingStage stage = PairingStage.idle;
  String? error;

  String? sas;
  bool localSasConfirmed = false;
  bool peerSasConfirmed = false;

  Uint8List? sessionId4;
  Uint8List? masterKey32;
  Uint8List? peerStaticPubkeyX25519;
  String? contactId;

  SecureChannel? _channel;
  NoiseXXInitiator? _i;
  NoiseXXResponder? _r;

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
    if (stage != PairingStage.sasReady && stage != PairingStage.waitingPeerSas) {
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
    _channel = null;
    _i = null;
    _r = null;
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
      // Allow idempotent replays only when still handshaking.
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

  Future<void> _finalizeHandshake(NoiseXXHandshakeResult result, {required bool isInitiator}) async {
    sessionId4 = sessionId4FromHandshakeHash(result.handshakeHash);
    sas = sasString6FromHandshakeHash(result.handshakeHash);
    peerStaticPubkeyX25519 = Uint8List.fromList(result.peerStaticPublicKey);

    final txKey = isInitiator ? result.initiatorToResponderKey : result.responderToInitiatorKey;
    final rxKey = isInitiator ? result.responderToInitiatorKey : result.initiatorToResponderKey;
    _channel = SecureChannel(sessionId4: sessionId4!, txKey: txKey, rxKey: rxKey);

    stage = PairingStage.sasReady;
    _onUpdate();
  }

  void _maybeProceedAfterSas() {
    if (stage == PairingStage.failed || stage == PairingStage.established) return;
    if (sas == null || sessionId4 == null || _channel == null) return;

    if (!localSasConfirmed || !peerSasConfirmed) {
      stage = PairingStage.waitingPeerSas;
      return;
    }

    if (role == ChatRole.initiator) {
      if (masterKey32 == null) {
        unawaited(_sendMasterKey());
      }
      stage = PairingStage.waitingMasterKeyAck;
      return;
    }

    stage = PairingStage.waitingMasterKey;
  }

  Future<void> _sendMasterKey() async {
    final channel = _channel;
    final sid = sessionId4;
    if (channel == null || sid == null) {
      _fail('cannot send master key: channel not ready');
      return;
    }
    final mk = randomBytes(32);
    masterKey32 = Uint8List.fromList(mk);
    final enc = await channel.encrypt(masterKey32!);
    await _send(_wrap(kSecMsgMasterKey, enc));
    _onUpdate();
  }

  Future<void> _onMasterKey(Uint8List payload) async {
    if (role != ChatRole.responder) {
      _fail('received master key but we are initiator');
      return;
    }
    if (_channel == null || peerStaticPubkeyX25519 == null) {
      _fail('received master key before channel/peer key ready');
      return;
    }
    if (stage != PairingStage.waitingPeerSas && stage != PairingStage.sasReady) {
      // Allow if peer races and sends quickly.
    }

    final mk = await _channel!.decrypt(payload);
    if (mk.length != 32) {
      _fail('master key length invalid');
      return;
    }
    masterKey32 = Uint8List.fromList(mk);

    final contact = await _storage.upsertTrustedContactFromStaticPubkey(
      peerStaticPubkeyX25519: peerStaticPubkeyX25519!,
    );
    contactId = contact.contactId;

    final ack = await _channel!.encrypt(Uint8List.fromList('ok'.codeUnits));
    await _send(_wrap(kSecMsgMasterKeyAck, ack));

    stage = PairingStage.established;
    _onUpdate();
  }

  Future<void> _onMasterKeyAck(Uint8List payload) async {
    if (role != ChatRole.initiator) {
      _fail('received master key ack but we are responder');
      return;
    }
    if (_channel == null || peerStaticPubkeyX25519 == null) {
      _fail('received ack before channel/peer key ready');
      return;
    }
    if (stage != PairingStage.waitingMasterKeyAck) {
      _fail('received ack in unexpected stage: $stage');
      return;
    }

    await _channel!.decrypt(payload);

    final contact = await _storage.upsertTrustedContactFromStaticPubkey(
      peerStaticPubkeyX25519: peerStaticPubkeyX25519!,
    );
    contactId = contact.contactId;

    stage = PairingStage.established;
    _onUpdate();
  }

  void _fail(String msg) {
    stage = PairingStage.failed;
    error = msg;
    _onUpdate();
  }
}
