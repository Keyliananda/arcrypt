import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ble_spike/transport/relay_inbox.dart';
import 'package:ble_spike/transport/relay_link.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stableJsonEncode sorts keys recursively', () {
    final encoded = stableJsonEncode({
      'z': 1,
      'a': {'d': true, 'b': false},
      'm': [3, 2, 1],
    });
    expect(encoded, '{"a":{"b":false,"d":true},"m":[3,2,1],"z":1}');
  });

  test('push retries once and sends valid proof', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    var attempts = 0;
    var proofWasValid = false;

    unawaited(
      server.listen((request) async {
        final bodyText = await utf8.decoder.bind(request).join();
        final body = jsonDecode(bodyText) as Map<String, dynamic>;
        attempts++;

        final unsigned = Map<String, dynamic>.from(body)..remove('proof');
        final expectedProof = _computeExpectedProof(
          mailboxId: body['mailbox_id'] as String,
          method: 'POST',
          path: request.uri.path,
          ts: body['ts'] as int,
          nonce: body['nonce'] as String,
          bodyWithoutProof: unsigned,
        );
        proofWasValid = body['proof'] == expectedProof;

        if (attempts == 1) {
          request.response.statusCode = 503;
          request.response.write('{"ok":false,"error":"relay_unavailable"}');
        } else {
          request.response.statusCode = 202;
          request.response.write(
            '{"ok":true,"message_id":"msg_1","expires_at":"2026-02-10T12:00:00Z","status":"queued"}',
          );
        }
        await request.response.close();
      }).asFuture<void>(),
    );

    final client = RelayMailboxHttpClient(
      config: RelayLinkConfig(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        requestTimeout: const Duration(seconds: 2),
        maxRetries: 2,
        initialBackoff: const Duration(milliseconds: 5),
        maxBackoff: const Duration(milliseconds: 10),
        jitterFactor: 0,
        random: Random(7),
        now: () => DateTime.utc(2026, 2, 9, 12, 0, 0),
      ),
    );
    addTearDown(() => client.close(force: true));

    final result = await client.push(
      mailboxId: 'bWFpbGJveC1pZC0xMjM0NTY3ODkw',
      ciphertext: Uint8List.fromList(<int>[1, 2, 3]),
      clientMsgId: 'cid-1',
    );

    expect(attempts, 2);
    expect(proofWasValid, isTrue);
    expect(result.messageId, 'msg_1');
    expect(result.status, 'queued');
    expect(result.expiresAt, DateTime.parse('2026-02-10T12:00:00Z'));
  });

  test('relay link pollOnce pulls, emits inbound bytes, and acks', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final ackedIds = <String>[];

    unawaited(
      server.listen((request) async {
        final bodyText = await utf8.decoder.bind(request).join();
        final body = jsonDecode(bodyText) as Map<String, dynamic>;
        if (request.uri.path == '/v1/mailbox/pull') {
          request.response.statusCode = 200;
          request.response.write(
            '{"ok":true,"messages":[{"message_id":"msg_42","ciphertext":"AQID","created_at":"2026-02-09T12:00:00Z","expires_at":"2026-02-10T12:00:00Z","size_bytes":3}],"next_cursor":null,"has_more":false}',
          );
        } else if (request.uri.path == '/v1/mailbox/ack') {
          final ids = (body['message_ids'] as List).cast<String>();
          ackedIds.addAll(ids);
          request.response.statusCode = 200;
          request.response.write(
            '{"ok":true,"acked":["msg_42"],"unknown":[],"already_acked":[]}',
          );
        } else {
          request.response.statusCode = 404;
          request.response.write('{"ok":false,"error":"not_found"}');
        }
        await request.response.close();
      }).asFuture<void>(),
    );

    final client = RelayMailboxHttpClient(
      config: RelayLinkConfig(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        requestTimeout: const Duration(seconds: 2),
        maxRetries: 1,
        initialBackoff: const Duration(milliseconds: 5),
        maxBackoff: const Duration(milliseconds: 10),
        jitterFactor: 0,
        random: Random(11),
        now: () => DateTime.utc(2026, 2, 9, 12, 0, 0),
      ),
    );
    addTearDown(() => client.close(force: true));

    final inbound = <Uint8List>[];
    final relayLink = RelayLink(
      client: client,
      outboundMailboxId: 'b3V0Ym91bmQtbWFpbGJveC0xMjM0NTY3ODkw',
      inboundMailboxId: 'aW5ib3VuZC1tYWlsYm94LTEyMzQ1Njc4OTA',
      onInboundCiphertext: (bytes) => inbound.add(Uint8List.fromList(bytes)),
      defaultAutoAck: true,
    );

    final result = await relayLink.pollOnce();

    expect(result.pull.messages, hasLength(1));
    expect(inbound, hasLength(1));
    expect(inbound.first, Uint8List.fromList(<int>[1, 2, 3]));
    expect(ackedIds, <String>['msg_42']);
    expect(result.ack, isNotNull);
    expect(result.ack!.acked, <String>['msg_42']);
  });

  test(
    'relay link with inbox queue dedupes pulled duplicates across polls',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      unawaited(
        server.listen((request) async {
          if (request.uri.path == '/v1/mailbox/pull') {
            request.response.statusCode = 200;
            request.response.write(
              '{"ok":true,"messages":[{"message_id":"msg_7","ciphertext":"AQID","created_at":"2026-02-09T12:00:00Z","expires_at":"2026-02-10T12:00:00Z","size_bytes":3}],"next_cursor":null,"has_more":false}',
            );
          } else if (request.uri.path == '/v1/mailbox/ack') {
            fail('ack must not be called when autoAck=false');
          } else {
            request.response.statusCode = 404;
            request.response.write('{"ok":false,"error":"not_found"}');
          }
          await request.response.close();
        }).asFuture<void>(),
      );

      final client = RelayMailboxHttpClient(
        config: RelayLinkConfig(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          requestTimeout: const Duration(seconds: 2),
          maxRetries: 1,
          initialBackoff: const Duration(milliseconds: 5),
          maxBackoff: const Duration(milliseconds: 10),
          jitterFactor: 0,
          random: Random(13),
          now: () => DateTime.utc(2026, 2, 9, 12, 0, 0),
        ),
      );
      addTearDown(() => client.close(force: true));

      final inbound = <Uint8List>[];
      final relayLink = RelayLink(
        client: client,
        outboundMailboxId: 'b3V0Ym91bmQtbWFpbGJveC0xMjM0NTY3ODkw',
        inboundMailboxId: 'aW5ib3VuZC1tYWlsYm94LTEyMzQ1Njc4OTA',
        onInboundCiphertext: (bytes) => inbound.add(Uint8List.fromList(bytes)),
        inboxQueue: RelayInboxQueue(store: _MemoryRelayInboxStore()),
        defaultAutoAck: false,
      );

      await relayLink.pollOnce();
      await relayLink.pollOnce();

      expect(inbound, hasLength(1));
      expect(inbound.first, Uint8List.fromList(<int>[1, 2, 3]));
    },
  );

  test('relay polling loop polls repeatedly and stops cleanly', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    var pullCount = 0;
    var ackCount = 0;
    final reachedThreePulls = Completer<void>();

    unawaited(
      server.listen((request) async {
        if (request.uri.path == '/v1/mailbox/pull') {
          pullCount++;
          if (pullCount >= 3 && !reachedThreePulls.isCompleted) {
            reachedThreePulls.complete();
          }
          request.response.statusCode = 200;
          request.response.write(
            '{"ok":true,"messages":[],"next_cursor":null,"has_more":false}',
          );
        } else if (request.uri.path == '/v1/mailbox/ack') {
          ackCount++;
          request.response.statusCode = 200;
          request.response.write(
            '{"ok":true,"acked":[],"unknown":[],"already_acked":[]}',
          );
        } else {
          request.response.statusCode = 404;
          request.response.write('{"ok":false,"error":"not_found"}');
        }
        await request.response.close();
      }).asFuture<void>(),
    );

    final client = RelayMailboxHttpClient(
      config: RelayLinkConfig(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        requestTimeout: const Duration(seconds: 2),
        maxRetries: 1,
        initialBackoff: const Duration(milliseconds: 5),
        maxBackoff: const Duration(milliseconds: 10),
        jitterFactor: 0,
        random: Random(17),
        now: () => DateTime.utc(2026, 2, 9, 12, 0, 0),
      ),
    );
    addTearDown(() => client.close(force: true));

    final relayLink = RelayLink(
      client: client,
      outboundMailboxId: 'b3V0Ym91bmQtbWFpbGJveC0xMjM0NTY3ODkw',
      inboundMailboxId: 'aW5ib3VuZC1tYWlsYm94LTEyMzQ1Njc4OTA',
      defaultAutoAck: true,
    );
    final poller = RelayPollingLoop(
      link: relayLink,
      config: const RelayPollingConfig(
        interval: Duration(milliseconds: 20),
        jitterFactor: 0,
        pollImmediately: true,
        maxBurstPerTick: 1,
      ),
      random: Random(19),
    );
    addTearDown(() => poller.stop());

    poller.start();
    await reachedThreePulls.future.timeout(const Duration(seconds: 2));
    await poller.stop();

    final pullsAfterStop = pullCount;
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(pullCount, pullsAfterStop);
    expect(pullCount, greaterThanOrEqualTo(3));
    expect(ackCount, 0);
  });

  test('relay polling loop drains has_more within one cycle', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    var pullCount = 0;
    final ackedIds = <String>[];
    final inbound = <Uint8List>[];
    final reachedThirdPull = Completer<void>();

    unawaited(
      server.listen((request) async {
        if (request.uri.path == '/v1/mailbox/pull') {
          pullCount++;
          final messageId = 'msg_$pullCount';
          final hasMore = pullCount < 3;
          final nextCursor = hasMore ? '"cursor_$pullCount"' : 'null';
          final payloadB64 = base64Encode(<int>[pullCount, pullCount + 1]);
          request.response.statusCode = 200;
          request.response.write(
            '{"ok":true,"messages":[{"message_id":"$messageId","ciphertext":"$payloadB64"}],"next_cursor":$nextCursor,"has_more":${hasMore ? 'true' : 'false'}}',
          );
          if (pullCount == 3 && !reachedThirdPull.isCompleted) {
            reachedThirdPull.complete();
          }
        } else if (request.uri.path == '/v1/mailbox/ack') {
          final bodyText = await utf8.decoder.bind(request).join();
          final body = jsonDecode(bodyText) as Map<String, dynamic>;
          final ids = (body['message_ids'] as List).cast<String>();
          ackedIds.addAll(ids);
          request.response.statusCode = 200;
          request.response.write(
            '{"ok":true,"acked":${jsonEncode(ids)},"unknown":[],"already_acked":[]}',
          );
        } else {
          request.response.statusCode = 404;
          request.response.write('{"ok":false,"error":"not_found"}');
        }
        await request.response.close();
      }).asFuture<void>(),
    );

    final client = RelayMailboxHttpClient(
      config: RelayLinkConfig(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        requestTimeout: const Duration(seconds: 2),
        maxRetries: 1,
        initialBackoff: const Duration(milliseconds: 5),
        maxBackoff: const Duration(milliseconds: 10),
        jitterFactor: 0,
        random: Random(23),
        now: () => DateTime.utc(2026, 2, 9, 12, 0, 0),
      ),
    );
    addTearDown(() => client.close(force: true));

    final relayLink = RelayLink(
      client: client,
      outboundMailboxId: 'b3V0Ym91bmQtbWFpbGJveC0xMjM0NTY3ODkw',
      inboundMailboxId: 'aW5ib3VuZC1tYWlsYm94LTEyMzQ1Njc4OTA',
      onInboundCiphertext: (bytes) => inbound.add(Uint8List.fromList(bytes)),
      defaultAutoAck: true,
    );
    final poller = RelayPollingLoop(
      link: relayLink,
      config: const RelayPollingConfig(
        interval: Duration(seconds: 5),
        jitterFactor: 0,
        pollImmediately: true,
        maxBurstPerTick: 5,
      ),
      random: Random(29),
    );
    addTearDown(() => poller.stop());

    poller.start();
    await reachedThirdPull.future.timeout(const Duration(seconds: 2));
    await poller.stop();

    expect(pullCount, 3);
    expect(ackedIds, <String>['msg_1', 'msg_2', 'msg_3']);
    expect(inbound, <Uint8List>[
      Uint8List.fromList(<int>[1, 2]),
      Uint8List.fromList(<int>[2, 3]),
      Uint8List.fromList(<int>[3, 4]),
    ]);
  });

  test('computeJitteredInterval stays inside configured bounds', () {
    final random = _SequenceRandom(Queue<int>.from(<int>[0, 200]));
    final low = computeJitteredInterval(
      baseInterval: const Duration(seconds: 1),
      jitterFactor: 0.1,
      random: random,
    );
    final high = computeJitteredInterval(
      baseInterval: const Duration(seconds: 1),
      jitterFactor: 0.1,
      random: random,
    );

    expect(low, const Duration(milliseconds: 900));
    expect(high, const Duration(milliseconds: 1100));
  });
}

String _computeExpectedProof({
  required String mailboxId,
  required String method,
  required String path,
  required int ts,
  required String nonce,
  required Map<String, dynamic> bodyWithoutProof,
}) {
  final bodySha = sha256
      .convert(utf8.encode(_stableEncode(bodyWithoutProof)))
      .toString();
  final canonical = '${method.toUpperCase()}\n$path\n$ts\n$nonce\n$bodySha';
  return Hmac(
    sha256,
    utf8.encode(mailboxId),
  ).convert(utf8.encode(canonical)).toString();
}

String _stableEncode(Object? value) {
  return jsonEncode(_stableNormalize(value));
}

Object? _stableNormalize(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return value.map(_stableNormalize).toList(growable: false);
  }
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      sorted[entry.key as String] = _stableNormalize(entry.value);
    }
    return sorted;
  }
  throw ArgumentError('unsupported type');
}

class _MemoryRelayInboxStore implements RelayInboxStore {
  final Map<String, RelayInboxEntry> _entries = <String, RelayInboxEntry>{};

  @override
  Future<RelayInboxEntry?> getByMessageId(String messageId) async {
    final entry = _entries[messageId];
    if (entry == null) {
      return null;
    }
    return entry.copyWith();
  }

  @override
  Future<List<RelayInboxEntry>> listPending({required int limit}) async {
    final pending = _entries.values
        .where((entry) => entry.status == RelayInboxStatus.pending)
        .map((entry) => entry.copyWith())
        .toList(growable: false);
    pending.sort((a, b) {
      final bySeen = a.firstSeenAtMs.compareTo(b.firstSeenAtMs);
      if (bySeen != 0) {
        return bySeen;
      }
      return a.messageId.compareTo(b.messageId);
    });
    if (pending.length <= limit) {
      return pending;
    }
    return pending.sublist(0, limit);
  }

  @override
  Future<void> put(RelayInboxEntry entry) async {
    _entries[entry.messageId] = entry.copyWith();
  }

  @override
  Future<void> close() async {}
}

class _SequenceRandom implements Random {
  _SequenceRandom(this._values);

  final Queue<int> _values;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1 << 24) / (1 << 24);

  @override
  int nextInt(int max) {
    if (max <= 0) {
      throw ArgumentError.value(max, 'max', 'must be > 0');
    }
    if (_values.isEmpty) {
      return 0;
    }
    final value = _values.removeFirst();
    return value % max;
  }
}
