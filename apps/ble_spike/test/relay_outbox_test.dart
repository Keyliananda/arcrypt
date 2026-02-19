import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ble_spike/transport/relay_link.dart';
import 'package:ble_spike/transport/relay_outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('relay-outbox-test-');
    Hive.init(hiveDir.path);
    registerRelayOutboxAdapter();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  test('pending entries survive restart and are flushed later', () async {
    final boxName = _uniqueBoxName();

    final firstStore = await HiveRelayOutboxStore.open(boxName: boxName);
    final firstQueue = RelayOutboxQueue(
      store: firstStore,
      sender: ({required ciphertext, required clientMsgId}) async {
        fail('sender must not be used during enqueue-only phase');
      },
    );
    await firstQueue.enqueue(
      ciphertext: Uint8List.fromList(<int>[1, 2, 3]),
      clientMsgId: 'client_1',
    );
    await firstStore.close();

    var calls = 0;
    final secondStore = await HiveRelayOutboxStore.open(boxName: boxName);
    final secondQueue = RelayOutboxQueue(
      store: secondStore,
      sender: ({required ciphertext, required clientMsgId}) async {
        calls++;
        expect(clientMsgId, 'client_1');
        expect(ciphertext, Uint8List.fromList(<int>[1, 2, 3]));
        return RelayPushResult(
          messageId: 'msg_1',
          status: 'queued',
          expiresAt: DateTime.utc(2026, 2, 10),
        );
      },
    );

    final flush = await secondQueue.flushPending();
    expect(flush.processed, 1);
    expect(flush.sent, 1);
    expect(flush.retryScheduled, 0);
    expect(flush.failed, 0);
    expect(calls, 1);

    final stored = await secondStore.getByClientMsgId('client_1');
    expect(stored, isNotNull);
    expect(stored!.status, RelayOutboxStatus.sent);
    expect(stored.relayMessageId, 'msg_1');
    expect(stored.attempts, 1);

    await secondStore.close();
    await Hive.deleteBoxFromDisk(boxName);
  });

  test('enqueue is idempotent and prevents double-sends', () async {
    final boxName = _uniqueBoxName();
    var calls = 0;

    final store = await HiveRelayOutboxStore.open(boxName: boxName);
    final queue = RelayOutboxQueue(
      store: store,
      sender: ({required ciphertext, required clientMsgId}) async {
        calls++;
        return RelayPushResult(
          messageId: 'msg_dedup',
          status: 'queued',
          expiresAt: null,
        );
      },
    );

    await queue.enqueue(
      ciphertext: Uint8List.fromList(<int>[4, 5, 6]),
      clientMsgId: 'same_id',
    );
    final firstFlush = await queue.flushPending();
    expect(firstFlush.sent, 1);
    expect(calls, 1);

    final existing = await queue.enqueue(
      ciphertext: Uint8List.fromList(<int>[4, 5, 6]),
      clientMsgId: 'same_id',
    );
    expect(existing.status, RelayOutboxStatus.sent);

    final secondFlush = await queue.flushPending();
    expect(secondFlush.processed, 0);
    expect(calls, 1);

    await expectLater(
      queue.enqueue(
        ciphertext: Uint8List.fromList(<int>[7, 8, 9]),
        clientMsgId: 'same_id',
      ),
      throwsStateError,
    );

    await store.close();
    await Hive.deleteBoxFromDisk(boxName);
  });

  test('retryable failures stay pending and are retried', () async {
    final boxName = _uniqueBoxName();
    var calls = 0;

    final store = await HiveRelayOutboxStore.open(boxName: boxName);
    final queue = RelayOutboxQueue(
      store: store,
      sender: ({required ciphertext, required clientMsgId}) async {
        calls++;
        if (calls == 1) {
          throw RelayLinkException('temporary', retryable: true);
        }
        return RelayPushResult(
          messageId: 'msg_retry',
          status: 'queued',
          expiresAt: null,
        );
      },
    );

    await queue.enqueue(
      ciphertext: Uint8List.fromList(<int>[10, 11, 12]),
      clientMsgId: 'retry_id',
    );

    final firstFlush = await queue.flushPending();
    expect(firstFlush.processed, 1);
    expect(firstFlush.sent, 0);
    expect(firstFlush.retryScheduled, 1);
    expect(firstFlush.failed, 0);

    final pending = await store.getByClientMsgId('retry_id');
    expect(pending, isNotNull);
    expect(pending!.status, RelayOutboxStatus.pending);
    expect(pending.attempts, 1);

    final secondFlush = await queue.flushPending();
    expect(secondFlush.processed, 1);
    expect(secondFlush.sent, 1);
    expect(secondFlush.retryScheduled, 0);
    expect(secondFlush.failed, 0);
    expect(calls, 2);

    final sent = await store.getByClientMsgId('retry_id');
    expect(sent, isNotNull);
    expect(sent!.status, RelayOutboxStatus.sent);
    expect(sent.attempts, 2);
    expect(sent.relayMessageId, 'msg_retry');

    await store.close();
    await Hive.deleteBoxFromDisk(boxName);
  });

  test('preserves enqueue order when timestamps are equal', () async {
    final boxName = _uniqueBoxName();
    final sentOrder = <String>[];
    final fixedNow = DateTime.utc(2026, 2, 19, 16, 0, 0);

    final store = await HiveRelayOutboxStore.open(boxName: boxName);
    final queue = RelayOutboxQueue(
      store: store,
      now: () => fixedNow,
      sender: ({required ciphertext, required clientMsgId}) async {
        sentOrder.add(clientMsgId);
        return RelayPushResult(
          messageId: 'msg_$clientMsgId',
          status: 'queued',
          expiresAt: null,
        );
      },
    );

    await queue.enqueue(
      ciphertext: Uint8List.fromList(<int>[1]),
      clientMsgId: 'z-first',
    );
    await queue.enqueue(
      ciphertext: Uint8List.fromList(<int>[2]),
      clientMsgId: 'a-second',
    );

    final flush = await queue.flushPending(limit: 10);
    expect(flush.sent, 2);
    expect(sentOrder, <String>['z-first', 'a-second']);

    await store.close();
    await Hive.deleteBoxFromDisk(boxName);
  });

  test('serializes concurrent flushes to avoid duplicate sends', () async {
    final boxName = _uniqueBoxName();
    final sentOrder = <String>[];
    var firstSend = true;

    final store = await HiveRelayOutboxStore.open(boxName: boxName);
    final queue = RelayOutboxQueue(
      store: store,
      sender: ({required ciphertext, required clientMsgId}) async {
        sentOrder.add(clientMsgId);
        if (firstSend) {
          firstSend = false;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        return RelayPushResult(
          messageId: 'msg_$clientMsgId',
          status: 'queued',
          expiresAt: null,
        );
      },
    );

    await queue.enqueue(
      ciphertext: Uint8List.fromList(<int>[10]),
      clientMsgId: 'one',
    );
    await queue.enqueue(
      ciphertext: Uint8List.fromList(<int>[11]),
      clientMsgId: 'two',
    );

    final flushA = queue.flushPending(limit: 1);
    final flushB = queue.flushPending(limit: 10);
    final resultA = await flushA;
    final resultB = await flushB;

    expect(resultA.sent + resultB.sent, 2);
    expect(sentOrder, <String>['one', 'two']);

    final one = await store.getByClientMsgId('one');
    final two = await store.getByClientMsgId('two');
    expect(one?.status, RelayOutboxStatus.sent);
    expect(two?.status, RelayOutboxStatus.sent);
    expect(one?.attempts, 1);
    expect(two?.attempts, 1);

    await store.close();
    await Hive.deleteBoxFromDisk(boxName);
  });

  test('failPending marks queued entries as failed', () async {
    final boxName = _uniqueBoxName();

    final store = await HiveRelayOutboxStore.open(boxName: boxName);
    final queue = RelayOutboxQueue(
      store: store,
      sender: ({required ciphertext, required clientMsgId}) async {
        fail('sender must not run for failPending');
      },
    );

    await queue.enqueue(
      ciphertext: Uint8List.fromList(<int>[1]),
      clientMsgId: 'pending_1',
    );
    await queue.enqueue(
      ciphertext: Uint8List.fromList(<int>[2]),
      clientMsgId: 'pending_2',
    );

    final quarantined = await queue.failPending(reason: 'test-quarantine');
    expect(quarantined, 2);

    final first = await store.getByClientMsgId('pending_1');
    final second = await store.getByClientMsgId('pending_2');
    expect(first?.status, RelayOutboxStatus.failed);
    expect(second?.status, RelayOutboxStatus.failed);
    expect(first?.lastError, contains('test-quarantine'));
    expect(second?.lastError, contains('test-quarantine'));

    final flush = await queue.flushPending();
    expect(flush.processed, 0);

    await store.close();
    await Hive.deleteBoxFromDisk(boxName);
  });
}

String _uniqueBoxName() {
  final random = Random();
  final suffix = random.nextInt(1 << 32);
  return 'relay_outbox_test_${DateTime.now().microsecondsSinceEpoch}_$suffix';
}
