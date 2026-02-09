import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ble_spike/transport/relay_inbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('relay-inbox-test-');
    Hive.init(hiveDir.path);
    registerRelayInboxAdapter();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  test('pending entries survive restart and are delivered once', () async {
    final boxName = _uniqueBoxName();
    final t0 = DateTime.utc(2026, 2, 9, 10, 0, 0);

    final firstStore = await HiveRelayInboxStore.open(boxName: boxName);
    final firstQueue = RelayInboxQueue(store: firstStore, now: () => t0);
    final firstEnqueue = await firstQueue.enqueuePulled(
      messages: <RelayInboxIncomingMessage>[
        RelayInboxIncomingMessage(
          messageId: 'msg_1',
          ciphertext: Uint8List.fromList(<int>[1, 2, 3]),
          createdAt: DateTime.utc(2026, 2, 9, 9, 0, 0),
        ),
      ],
    );
    expect(firstEnqueue.inserted, 1);
    await firstStore.close();

    final secondStore = await HiveRelayInboxStore.open(boxName: boxName);
    final secondQueue = RelayInboxQueue(
      store: secondStore,
      now: () => t0.add(const Duration(minutes: 1)),
    );

    final secondEnqueue = await secondQueue.enqueuePulled(
      messages: <RelayInboxIncomingMessage>[
        RelayInboxIncomingMessage(
          messageId: 'msg_1',
          ciphertext: Uint8List.fromList(<int>[1, 2, 3]),
          createdAt: DateTime.utc(2026, 2, 9, 8, 0, 0),
        ),
        RelayInboxIncomingMessage(
          messageId: 'msg_2',
          ciphertext: Uint8List.fromList(<int>[9, 8, 7]),
          createdAt: DateTime.utc(2026, 2, 9, 7, 0, 0),
        ),
      ],
    );
    expect(secondEnqueue.processed, 2);
    expect(secondEnqueue.inserted, 1);
    expect(secondEnqueue.duplicates, 1);

    final deliveredOrder = <String>[];
    final drain = await secondQueue.drainPending(
      limit: 10,
      onEntry: (entry) async {
        deliveredOrder.add(entry.messageId);
      },
    );
    expect(drain.processed, 2);
    expect(drain.delivered, 2);
    expect(deliveredOrder, <String>['msg_1', 'msg_2']);

    final drainAgain = await secondQueue.drainPending(
      limit: 10,
      onEntry: (entry) async {
        fail('already delivered entries must not be re-delivered');
      },
    );
    expect(drainAgain.processed, 0);
    expect(drainAgain.delivered, 0);

    await secondStore.close();

    final thirdStore = await HiveRelayInboxStore.open(boxName: boxName);
    final thirdQueue = RelayInboxQueue(store: thirdStore);
    final restartDrain = await thirdQueue.drainPending(
      limit: 10,
      onEntry: (entry) async {
        fail('delivered status must survive restarts');
      },
    );
    expect(restartDrain.delivered, 0);
    await thirdStore.close();

    await Hive.deleteBoxFromDisk(boxName);
  });

  test('message_id collision with different ciphertext fails', () async {
    final boxName = _uniqueBoxName();
    final store = await HiveRelayInboxStore.open(boxName: boxName);
    final queue = RelayInboxQueue(store: store);

    await queue.enqueuePulled(
      messages: <RelayInboxIncomingMessage>[
        RelayInboxIncomingMessage(
          messageId: 'msg_collision',
          ciphertext: Uint8List.fromList(<int>[4, 5, 6]),
        ),
      ],
    );

    await expectLater(
      queue.enqueuePulled(
        messages: <RelayInboxIncomingMessage>[
          RelayInboxIncomingMessage(
            messageId: 'msg_collision',
            ciphertext: Uint8List.fromList(<int>[7, 8, 9]),
          ),
        ],
      ),
      throwsStateError,
    );

    await store.close();
    await Hive.deleteBoxFromDisk(boxName);
  });

  test('drainPending rejects invalid limits', () async {
    final boxName = _uniqueBoxName();
    final store = await HiveRelayInboxStore.open(boxName: boxName);
    final queue = RelayInboxQueue(store: store);

    await expectLater(
      queue.drainPending(limit: 0, onEntry: (entry) async {}),
      throwsArgumentError,
    );

    await store.close();
    await Hive.deleteBoxFromDisk(boxName);
  });
}

String _uniqueBoxName() {
  final random = Random();
  final suffix = random.nextInt(1 << 32);
  return 'relay_inbox_test_${DateTime.now().microsecondsSinceEpoch}_$suffix';
}
