import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ble_spike/chat/chat.dart';

Uint8List _bytes(int length, int seed) {
  return Uint8List.fromList(
    List<int>.generate(length, (i) => (i + seed) & 0xFF),
  );
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

    final outbound = await initiator.encryptText(body: 'replay', sentAtMs: 100);

    await responder.decryptFrame(outbound.frame);

    expect(
      () async => responder.decryptFrame(outbound.frame),
      throwsA(isA<ChatDecodeException>()),
    );
  });

  test('uses reserved tx counter and commits rx counter', () async {
    final sessionId = _bytes(4, 15);
    final masterKey = _bytes(32, 19);
    final reservedCounters = <int>[7];
    var reserveCalls = 0;
    var committedRxCounter = -1;

    final initiator = ChatSession(
      contactId: 'contact-3',
      sessionId: sessionId,
      keyId: 'key-3',
      masterKey: masterKey,
      role: ChatRole.initiator,
      reserveTxCounter: () async {
        final c = reservedCounters[reserveCalls];
        reserveCalls += 1;
        return c;
      },
    );

    final responder = ChatSession(
      contactId: 'contact-3',
      sessionId: sessionId,
      keyId: 'key-3',
      masterKey: masterKey,
      role: ChatRole.responder,
      lastRxCounter: 6,
      commitRxCounter: (counter) async {
        committedRxCounter = counter;
      },
    );

    final outbound = await initiator.encryptText(
      body: 'counter-state',
      sentAtMs: 123,
    );
    expect(outbound.message.counter, 7);
    expect(initiator.txCounter, 8);

    final inbound = await responder.decryptFrame(outbound.frame);
    expect(inbound.message.counter, 7);
    expect(committedRxCounter, 7);
    expect(responder.lastRxCounter, 7);
  });

  test('accepts out-of-order frames within replay window', () async {
    final sessionId = _bytes(4, 22);
    final masterKey = _bytes(32, 31);
    final committed = <int>[];

    final initiator = ChatSession(
      contactId: 'contact-4',
      sessionId: sessionId,
      keyId: 'key-4',
      masterKey: masterKey,
      role: ChatRole.initiator,
    );
    final responder = ChatSession(
      contactId: 'contact-4',
      sessionId: sessionId,
      keyId: 'key-4',
      masterKey: masterKey,
      role: ChatRole.responder,
      commitRxCounter: (counter) async => committed.add(counter),
    );

    final m0 = await initiator.encryptText(body: 'm0');
    final m1 = await initiator.encryptText(body: 'm1');
    final m2 = await initiator.encryptText(body: 'm2');

    final in2 = await responder.decryptFrame(m2.frame);
    final in1 = await responder.decryptFrame(m1.frame);
    final in0 = await responder.decryptFrame(m0.frame);

    expect(in2.message.bodyUtf8, 'm2');
    expect(in1.message.bodyUtf8, 'm1');
    expect(in0.message.bodyUtf8, 'm0');
    expect(committed, <int>[2, 1, 0]);
    expect(responder.lastRxCounter, 2);

    expect(
      () async => responder.decryptFrame(m1.frame),
      throwsA(isA<ChatDecodeException>()),
    );
  });

  test('rejects frames that fall outside replay window', () async {
    final sessionId = _bytes(4, 41);
    final masterKey = _bytes(32, 51);

    final initiator = ChatSession(
      contactId: 'contact-5',
      sessionId: sessionId,
      keyId: 'key-5',
      masterKey: masterKey,
      role: ChatRole.initiator,
    );
    final responder = ChatSession(
      contactId: 'contact-5',
      sessionId: sessionId,
      keyId: 'key-5',
      masterKey: masterKey,
      role: ChatRole.responder,
    );

    final frames = <Uint8List>[];
    for (var i = 0; i < 70; i++) {
      final outbound = await initiator.encryptText(body: 'm$i');
      frames.add(outbound.frame);
    }

    await responder.decryptFrame(frames[69]);
    expect(
      () async => responder.decryptFrame(frames[0]),
      throwsA(
        isA<ChatDecodeException>().having(
          (e) => e.message,
          'message',
          contains('window'),
        ),
      ),
    );
  });
}
