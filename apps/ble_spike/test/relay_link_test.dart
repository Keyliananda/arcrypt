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
