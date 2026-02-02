import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ble_spike/chat/chat.dart';

Uint8List _bytes(int length, int seed) {
  return Uint8List.fromList(List<int>.generate(length, (i) => (i + seed) & 0xFF));
}

testWidgetsBinding() {
  TestWidgetsFlutterBinding.ensureInitialized();
}

void main() {
  testWidgetsBinding();

  test('encrypt/decrypt roundtrip', () async {
    final sessionId = _bytes(4, 1);
    final masterKey = _bytes(32, 7);
    final messageId = base64UrlEncodeNoPad(_bytes(16, 3));

    final initiator = ChatSession(
      contactId: 'contact-1',
      sessionId: sessionId,
      keyId: 'key-1',
      masterKey: masterKey,
      role: ChatRole.initiator,
    );

    final responder = ChatSession(
      contactId: 'contact-1',
      sessionId: sessionId,
      keyId: 'key-1',
      masterKey: masterKey,
      role: ChatRole.responder,
    );

    final outbound = await initiator.encryptText(
      body: 'hello',
      messageId: messageId,
      sentAtMs: 42,
    );

    final inbound = await responder.decryptFrame(outbound.frame);

    expect(inbound.message.bodyUtf8, 'hello');
    expect(inbound.message.messageId, outbound.message.messageId);
    expect(inbound.message.counter, outbound.message.counter);
  });

  test('replay detection drops duplicate frames', () async {
    final sessionId = _bytes(4, 9);
    final masterKey = _bytes(32, 11);

    final initiator = ChatSession(
      contactId: 'contact-2',
      sessionId: sessionId,
      keyId: 'key-2',
      masterKey: masterKey,
      role: ChatRole.initiator,
    );

    final responder = ChatSession(
      contactId: 'contact-2',
      sessionId: sessionId,
      keyId: 'key-2',
      masterKey: masterKey,
      role: ChatRole.responder,
    );

    final outbound = await initiator.encryptText(
      body: 'replay',
      sentAtMs: 100,
    );

    await responder.decryptFrame(outbound.frame);

    expect(
      () async => responder.decryptFrame(outbound.frame),
      throwsA(isA<ChatDecodeException>()),
    );
  });
}
