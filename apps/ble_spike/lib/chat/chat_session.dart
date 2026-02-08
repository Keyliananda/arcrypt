import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'chat_crypto.dart';
import 'chat_ids.dart';
import 'chat_models.dart';

const int kChatPayloadHeaderLength = 24;

enum ChatRole { initiator, responder }

class ChatCounterExhausted implements Exception {
  ChatCounterExhausted(this.message);

  final String message;

  @override
  String toString() => 'ChatCounterExhausted: $message';
}

class ChatEncodeException implements Exception {
  ChatEncodeException(this.message);

  final String message;

  @override
  String toString() => 'ChatEncodeException: $message';
}

class ChatDecodeException implements Exception {
  ChatDecodeException(this.message);

  final String message;

  @override
  String toString() => 'ChatDecodeException: $message';
}

class ChatOutboundResult {
  ChatOutboundResult({required this.message, required this.frame});

  final ChatMessage message;
  final Uint8List frame;
}

class ChatInboundResult {
  ChatInboundResult({required this.message});

  final ChatMessage message;
}

typedef ReserveTxCounter = Future<int> Function();
typedef CommitRxCounter = Future<void> Function(int counter);

class ChatSession {
  ChatSession({
    required this.contactId,
    required Uint8List sessionId,
    required this.keyId,
    required Uint8List masterKey,
    this.role = ChatRole.initiator,
    int txCounter = 0,
    int lastRxCounter = -1,
    ReserveTxCounter? reserveTxCounter,
    CommitRxCounter? commitRxCounter,
    ChatCrypto? crypto,
  }) : _sessionId = Uint8List.fromList(sessionId),
       _masterKey = SecretKey(masterKey),
       _txCounter = txCounter,
       _lastRxCounter = lastRxCounter,
       _reserveTxCounter = reserveTxCounter,
       _commitRxCounter = commitRxCounter,
       _crypto = crypto ?? ChatCrypto() {
    if (_sessionId.length != 4) {
      throw ArgumentError('sessionId must be 4 bytes');
    }
    if (masterKey.length != 32) {
      throw ArgumentError('masterKey must be 32 bytes');
    }
  }

  final String contactId;
  final String keyId;
  final ChatRole role;
  final Uint8List _sessionId;
  final SecretKey _masterKey;
  final ChatCrypto _crypto;
  final ReserveTxCounter? _reserveTxCounter;
  final CommitRxCounter? _commitRxCounter;

  int _txCounter;
  int _lastRxCounter;

  int get txCounter => _txCounter;
  int get lastRxCounter => _lastRxCounter;
  Uint8List get sessionIdBytes => Uint8List.fromList(_sessionId);

  // Direction bits are tied to handshake roles so both sides derive the same key.
  int get _outboundDirection => role == ChatRole.initiator ? 0 : 1;
  int get _inboundDirection => role == ChatRole.initiator ? 1 : 0;

  Future<ChatOutboundResult> encryptText({
    required String body,
    String? messageId,
    int? sentAtMs,
  }) async {
    final counter = _reserveTxCounter != null
        ? await _reserveTxCounter!.call()
        : _txCounter;
    if (counter >= kChatMaxCounter) {
      throw ChatCounterExhausted('tx counter exhausted');
    }

    final sentAt = sentAtMs ?? DateTime.now().millisecondsSinceEpoch;
    Uint8List msgIdBytes;
    if (messageId == null) {
      msgIdBytes = randomBytes(16);
    } else {
      try {
        msgIdBytes = base64UrlDecodeNoPad(messageId);
      } on FormatException {
        throw ChatEncodeException('message id is not base64url');
      }
    }

    if (msgIdBytes.length != 16) {
      throw ChatDecodeException('message id must be 16 bytes');
    }

    final payload = _encodeTextPayload(
      msgIdBytes: msgIdBytes,
      sentAtMs: sentAt,
      body: body,
    );

    if (payload.length > 0xFFFF) {
      throw ChatEncodeException('payload too large for header');
    }

    final header = ChatHeader(
      version: kChatVersion,
      type: kChatTypeText,
      counter: counter,
      payloadLength: payload.length,
    );
    final headerBytes = header.encode();

    final secretBox = await _crypto.encryptPayload(
      masterKey: _masterKey,
      sessionId: _sessionId,
      direction: _outboundDirection,
      counter: counter,
      header: headerBytes,
      plaintext: payload,
    );

    final frame = _assembleFrame(
      headerBytes,
      Uint8List.fromList(secretBox.cipherText),
      Uint8List.fromList(secretBox.mac.bytes),
    );

    final messageIdString = base64UrlEncodeNoPad(msgIdBytes);
    final message = ChatMessage(
      messageId: messageIdString,
      conversationId: contactId,
      direction: MessageDirection.outbound,
      status: MessageStatus.pending,
      sentAtMs: sentAt,
      receivedAtMs: 0,
      bodyUtf8: body,
      keyId: keyId,
      counter: counter,
      sessionId: _sessionIdAsInt(),
    );

    _txCounter = counter + 1;

    return ChatOutboundResult(message: message, frame: frame);
  }

  Future<ChatInboundResult> decryptFrame(Uint8List frame) async {
    if (frame.length < kChatHeaderLength + kChatTagLength) {
      throw ChatDecodeException('frame too short');
    }

    final header = ChatHeader.decode(frame.sublist(0, kChatHeaderLength));
    if (header.version != kChatVersion) {
      throw ChatDecodeException('unsupported version ${header.version}');
    }
    if (header.type != kChatTypeText) {
      throw ChatDecodeException('unsupported type ${header.type}');
    }
    if (header.counter <= _lastRxCounter) {
      throw ChatDecodeException('replay detected');
    }

    final expectedLength =
        kChatHeaderLength + header.payloadLength + kChatTagLength;
    if (frame.length != expectedLength) {
      throw ChatDecodeException('frame length mismatch');
    }

    final cipherText = frame.sublist(
      kChatHeaderLength,
      kChatHeaderLength + header.payloadLength,
    );
    final macBytes = frame.sublist(
      kChatHeaderLength + header.payloadLength,
      expectedLength,
    );

    final payload = await _crypto.decryptPayload(
      masterKey: _masterKey,
      sessionId: _sessionId,
      direction: _inboundDirection,
      counter: header.counter,
      header: frame.sublist(0, kChatHeaderLength),
      cipherText: cipherText,
      macBytes: macBytes,
    );

    final decoded = _decodeTextPayload(payload);

    final message = ChatMessage(
      messageId: decoded.messageId,
      conversationId: contactId,
      direction: MessageDirection.inbound,
      status: MessageStatus.received,
      sentAtMs: decoded.sentAtMs,
      receivedAtMs: DateTime.now().millisecondsSinceEpoch,
      bodyUtf8: decoded.body,
      keyId: keyId,
      counter: header.counter,
      sessionId: _sessionIdAsInt(),
    );

    if (_commitRxCounter != null) {
      await _commitRxCounter!.call(header.counter);
    }
    _lastRxCounter = header.counter;

    return ChatInboundResult(message: message);
  }

  Uint8List _encodeTextPayload({
    required Uint8List msgIdBytes,
    required int sentAtMs,
    required String body,
  }) {
    final bodyBytes = utf8.encode(body);
    final payload = Uint8List(kChatPayloadHeaderLength + bodyBytes.length);
    payload.setRange(0, 16, msgIdBytes);
    final timestampData = ByteData.sublistView(payload, 16, 24);
    timestampData.setUint64(0, sentAtMs, Endian.little);
    payload.setRange(24, payload.length, bodyBytes);
    return payload;
  }

  _DecodedPayload _decodeTextPayload(Uint8List payload) {
    if (payload.length < kChatPayloadHeaderLength) {
      throw ChatDecodeException('payload too short');
    }
    final msgIdBytes = payload.sublist(0, 16);
    final timestampData = ByteData.sublistView(payload, 16, 24);
    final sentAtMs = timestampData.getUint64(0, Endian.little);
    final bodyBytes = payload.sublist(24);
    final body = utf8.decode(bodyBytes);
    final messageId = base64UrlEncodeNoPad(Uint8List.fromList(msgIdBytes));
    return _DecodedPayload(
      messageId: messageId,
      sentAtMs: sentAtMs,
      body: body,
    );
  }

  int _sessionIdAsInt() {
    final data = ByteData.sublistView(_sessionId);
    return data.getUint32(0, Endian.little);
  }

  Uint8List _assembleFrame(
    Uint8List header,
    Uint8List cipherText,
    Uint8List macBytes,
  ) {
    final frame = Uint8List(
      header.length + cipherText.length + macBytes.length,
    );
    frame.setRange(0, header.length, header);
    frame.setRange(
      header.length,
      header.length + cipherText.length,
      cipherText,
    );
    frame.setRange(header.length + cipherText.length, frame.length, macBytes);
    return frame;
  }
}

class _DecodedPayload {
  _DecodedPayload({
    required this.messageId,
    required this.sentAtMs,
    required this.body,
  });

  final String messageId;
  final int sentAtMs;
  final String body;
}
