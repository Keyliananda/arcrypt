import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ble_spike/transport/relay_inbox.dart';
import 'package:ble_spike/transport/relay_link.dart';
import 'package:ble_spike/transport/relay_outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;
  late bool nodeAvailable;

  setUpAll(() async {
    nodeAvailable = await _isNodeAvailable();
    hiveDir = await Directory.systemTemp.createTemp(
      'relay-link-local-server-int-test-',
    );
    Hive.init(hiveDir.path);
    registerRelayOutboxAdapter();
    registerRelayInboxAdapter();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  test(
    'happy path: push -> pull -> ack works against local relay server',
    () async {
      if (!nodeAvailable) {
        return;
      }
      final harness = await _LocalRelayServerHarness.start();
      addTearDown(harness.stop);

      final mailboxId = _validMailboxId(seed: 11);
      final senderClient = _newRelayClient(baseUri: harness.baseUri);
      final receiverClient = _newRelayClient(baseUri: harness.baseUri);
      addTearDown(() => senderClient.close(force: true));
      addTearDown(() => receiverClient.close(force: true));

      final inboundPayloads = <Uint8List>[];
      final receiverLink = RelayLink(
        client: receiverClient,
        outboundMailboxId: _validMailboxId(seed: 12),
        inboundMailboxId: mailboxId,
        onInboundCiphertext: (bytes) {
          inboundPayloads.add(Uint8List.fromList(bytes));
        },
      );

      final senderLink = RelayLink(
        client: senderClient,
        outboundMailboxId: mailboxId,
        inboundMailboxId: _validMailboxId(seed: 13),
      );

      final pushed = await senderLink.pushCiphertext(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        clientMsgId: 'happy_path_1',
      );
      expect(pushed.status, 'queued');
      expect(pushed.messageId, startsWith('msg_'));

      final polled = await receiverLink.pollOnce();
      expect(polled.pull.messages, hasLength(1));
      expect(polled.ack, isNotNull);
      expect(polled.ack!.acked, <String>[pushed.messageId]);
      expect(inboundPayloads, hasLength(1));
      expect(inboundPayloads.single, Uint8List.fromList(<int>[1, 2, 3, 4]));

      final polledAfterAck = await receiverLink.pollOnce();
      expect(polledAfterAck.pull.messages, isEmpty);
    },
  );

  test(
    'offline + retry: pending outbox flush succeeds after server comes online',
    () async {
      if (!nodeAvailable) {
        return;
      }
      final port = await _reservePort();
      final baseUri = Uri.parse('http://127.0.0.1:$port');
      final mailboxId = _validMailboxId(seed: 21);

      final senderClient = _newRelayClient(
        baseUri: baseUri,
        requestTimeout: const Duration(milliseconds: 200),
        maxRetries: 0,
      );
      addTearDown(() => senderClient.close(force: true));

      final senderLink = RelayLink(
        client: senderClient,
        outboundMailboxId: mailboxId,
        inboundMailboxId: _validMailboxId(seed: 22),
      );

      final boxName = _uniqueBoxName('offline_retry');
      final store = await HiveRelayOutboxStore.open(boxName: boxName);
      addTearDown(() async {
        await store.close();
        await Hive.deleteBoxFromDisk(boxName);
      });

      final outbox = RelayOutboxQueue(
        store: store,
        sender: ({required ciphertext, required clientMsgId}) {
          return senderLink.pushCiphertext(
            ciphertext,
            clientMsgId: clientMsgId,
          );
        },
      );

      await outbox.enqueue(
        ciphertext: Uint8List.fromList(<int>[8, 9, 10]),
        clientMsgId: 'offline_retry_1',
      );

      final firstFlush = await outbox.flushPending();
      expect(firstFlush.processed, 1);
      expect(firstFlush.sent, 0);
      expect(firstFlush.retryScheduled, 1);
      expect(firstFlush.failed, 0);

      final harness = await _LocalRelayServerHarness.start(port: port);
      addTearDown(harness.stop);

      final secondFlush = await outbox.flushPending();
      expect(secondFlush.processed, 1);
      expect(secondFlush.sent, 1);
      expect(secondFlush.retryScheduled, 0);
      expect(secondFlush.failed, 0);

      final stored = await store.getByClientMsgId('offline_retry_1');
      expect(stored, isNotNull);
      expect(stored!.status, RelayOutboxStatus.sent);
      expect(stored.attempts, 2);

      final receiverClient = _newRelayClient(baseUri: harness.baseUri);
      addTearDown(() => receiverClient.close(force: true));
      final receiverLink = RelayLink(
        client: receiverClient,
        outboundMailboxId: _validMailboxId(seed: 23),
        inboundMailboxId: mailboxId,
      );

      final pulled = await receiverLink.pollOnce();
      expect(pulled.pull.messages, hasLength(1));
    },
  );

  test(
    'dedupe: repeated client_msg_id is idempotent and inbox dedupes repeated pulls',
    () async {
      if (!nodeAvailable) {
        return;
      }
      final harness = await _LocalRelayServerHarness.start();
      addTearDown(harness.stop);

      final mailboxId = _validMailboxId(seed: 31);
      final senderClient = _newRelayClient(baseUri: harness.baseUri);
      final receiverClient = _newRelayClient(baseUri: harness.baseUri);
      addTearDown(() => senderClient.close(force: true));
      addTearDown(() => receiverClient.close(force: true));

      final senderLink = RelayLink(
        client: senderClient,
        outboundMailboxId: mailboxId,
        inboundMailboxId: _validMailboxId(seed: 32),
      );

      final push1 = await senderLink.pushCiphertext(
        Uint8List.fromList(<int>[42, 43]),
        clientMsgId: 'dedupe_client_msg_id_1',
      );
      final push2 = await senderLink.pushCiphertext(
        Uint8List.fromList(<int>[42, 43]),
        clientMsgId: 'dedupe_client_msg_id_1',
      );
      expect(push2.messageId, push1.messageId);

      final inboxBoxName = _uniqueBoxName('inbox_dedupe');
      final inboxStore = await HiveRelayInboxStore.open(boxName: inboxBoxName);
      addTearDown(() async {
        await inboxStore.close();
        await Hive.deleteBoxFromDisk(inboxBoxName);
      });
      final inbox = RelayInboxQueue(store: inboxStore);

      final inboundPayloads = <Uint8List>[];
      final receiverLink = RelayLink(
        client: receiverClient,
        outboundMailboxId: _validMailboxId(seed: 33),
        inboundMailboxId: mailboxId,
        inboxQueue: inbox,
        onInboundCiphertext: (bytes) {
          inboundPayloads.add(Uint8List.fromList(bytes));
        },
      );

      final firstPoll = await receiverLink.pollOnce(autoAck: false);
      final secondPoll = await receiverLink.pollOnce(autoAck: false);
      expect(firstPoll.pull.messages, hasLength(1));
      expect(secondPoll.pull.messages, hasLength(1));
      expect(inboundPayloads, hasLength(1));
      expect(inboundPayloads.single, Uint8List.fromList(<int>[42, 43]));

      final ackResult = await receiverLink.ack(
        messageIds: <String>[push1.messageId],
      );
      expect(ackResult.acked, <String>[push1.messageId]);
    },
  );
}

RelayMailboxHttpClient _newRelayClient({
  required Uri baseUri,
  Duration requestTimeout = const Duration(seconds: 2),
  int maxRetries = 1,
}) {
  return RelayMailboxHttpClient(
    config: RelayLinkConfig(
      baseUri: baseUri,
      requestTimeout: requestTimeout,
      maxRetries: maxRetries,
      initialBackoff: const Duration(milliseconds: 20),
      maxBackoff: const Duration(milliseconds: 80),
      jitterFactor: 0,
      now: () => DateTime.now().toUtc(),
    ),
  );
}

Future<bool> _isNodeAvailable() async {
  try {
    final result = await Process.run('node', <String>['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

String _validMailboxId({required int seed}) {
  final random = Random(seed);
  final bytes = Uint8List(24);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _uniqueBoxName(String prefix) {
  final random = Random();
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 32)}';
}

class _LocalRelayServerHarness {
  _LocalRelayServerHarness._({
    required this.baseUri,
    required Process process,
    required Directory workDir,
    required File dbFile,
    required Directory tempDir,
    required StringBuffer stdoutBuffer,
    required StringBuffer stderrBuffer,
  }) : _process = process,
       _workDir = workDir,
       _dbFile = dbFile,
       _tempDir = tempDir,
       _stdoutBuffer = stdoutBuffer,
       _stderrBuffer = stderrBuffer;

  final Uri baseUri;
  final Process _process;
  final Directory _workDir;
  final File _dbFile;
  final Directory _tempDir;
  final StringBuffer _stdoutBuffer;
  final StringBuffer _stderrBuffer;
  bool _stopped = false;

  static Future<_LocalRelayServerHarness> start({int? port}) async {
    final selectedPort = port ?? await _reservePort();
    final repoRoot = _findRepoRoot();
    final serverDir = Directory('${repoRoot.path}/server');
    if (!await serverDir.exists()) {
      throw StateError('server directory not found at ${serverDir.path}');
    }

    final tempDir = await Directory.systemTemp.createTemp('relay-server-int-');
    final dbFile = File('${tempDir.path}/relay-int.sqlite');

    final env = <String, String>{
      ...Platform.environment,
      'PORT': '$selectedPort',
      'DB_DRIVER': 'sqlite',
      'DB_FILENAME': dbFile.path,
      'HMAC_SECRET': 'integration-secret',
      'APNS_ENABLED': 'false',
      'SECURITY_TLS_ONLY': 'false',
    };

    final initSchema = await Process.run(
      'node',
      <String>[
        '-e',
        '''
const fs = require('node:fs');
const path = require('node:path');
const sqlite3 = require('sqlite3');
const dbFile = process.argv[1];
const schema = fs.readFileSync(path.join(process.cwd(), 'schema_sqlite.sql'), 'utf8');
const db = new sqlite3.Database(dbFile);
db.exec(schema, (err) => {
  if (err) {
    process.stderr.write(String(err.message || err) + '\\n');
    process.exitCode = 1;
    db.close();
    return;
  }
  db.close((closeErr) => {
    if (closeErr) {
      process.stderr.write(String(closeErr.message || closeErr) + '\\n');
      process.exitCode = 1;
    }
  });
});
''',
        dbFile.path,
      ],
      workingDirectory: serverDir.path,
      environment: env,
    );
    if (initSchema.exitCode != 0) {
      final stderr = (initSchema.stderr ?? '').toString();
      throw StateError('schema init failed: ${stderr.trim()}');
    }

    final migrate = await Process.run(
      'node',
      <String>['scripts/migrate.js'],
      workingDirectory: serverDir.path,
      environment: env,
    );
    if (migrate.exitCode != 0) {
      final stderr = (migrate.stderr ?? '').toString();
      throw StateError('migration failed: ${stderr.trim()}');
    }

    final process = await Process.start(
      'node',
      <String>['src/server.js'],
      workingDirectory: serverDir.path,
      environment: env,
    );

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    process.stdout
        .transform(utf8.decoder)
        .listen((chunk) => stdoutBuffer.write(chunk));
    process.stderr
        .transform(utf8.decoder)
        .listen((chunk) => stderrBuffer.write(chunk));

    final harness = _LocalRelayServerHarness._(
      baseUri: Uri.parse('http://127.0.0.1:$selectedPort'),
      process: process,
      workDir: serverDir,
      dbFile: dbFile,
      tempDir: tempDir,
      stdoutBuffer: stdoutBuffer,
      stderrBuffer: stderrBuffer,
    );
    await harness._waitUntilHealthy();
    return harness;
  }

  Future<void> stop() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    if (_process.kill(ProcessSignal.sigterm)) {
      try {
        await _process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _process.kill(ProcessSignal.sigkill);
        await _process.exitCode;
      }
    } else {
      await _process.exitCode;
    }
    if (await _tempDir.exists()) {
      await _tempDir.delete(recursive: true);
    }
  }

  Future<void> _waitUntilHealthy() async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      final maybeExit = await _process.exitCode.timeout(
        const Duration(milliseconds: 1),
        onTimeout: () => -9999,
      );
      if (maybeExit != -9999) {
        throw StateError(
          'relay server exited early with code $maybeExit\n'
          'stdout:\n${_stdoutBuffer.toString().trim()}\n'
          'stderr:\n${_stderrBuffer.toString().trim()}',
        );
      }
      try {
        final ok = await _healthCheck(baseUri);
        if (ok) {
          return;
        }
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    throw StateError(
      'relay server did not become healthy in time '
      '(workdir=${_workDir.path}, db=${_dbFile.path})\n'
      'lastError=$lastError\n'
      'stdout:\n${_stdoutBuffer.toString().trim()}\n'
      'stderr:\n${_stderrBuffer.toString().trim()}',
    );
  }
}

Future<bool> _healthCheck(Uri baseUri) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(baseUri.resolve('/v1/health'));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode('{}'));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      return false;
    }
    final parsed = jsonDecode(body);
    return parsed is Map<String, dynamic> && parsed['ok'] == true;
  } finally {
    client.close(force: true);
  }
}

Directory _findRepoRoot() {
  var current = Directory.current;
  while (true) {
    final marker = File('${current.path}/server/package.json');
    if (marker.existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('repo root with server/package.json not found');
    }
    current = parent;
  }
}
