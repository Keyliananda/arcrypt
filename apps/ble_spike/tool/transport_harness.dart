import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:ble_spike/transport/transport.dart';

Future<void> main(List<String> args) async {
  final config = HarnessConfig.fromArgs(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  final rng = Random(config.seed);
  final link = MockDuplexLink(
    endpointA: 'A',
    endpointB: 'B',
    dropRate: config.dropRate,
    delay: Duration(milliseconds: config.delayMs),
    rng: rng,
  );

  final transportConfig = TransportConfig(
    maxPayload: config.maxPayload,
    maxMessageBytes: config.maxMessageBytes,
    ackTimeout: Duration(milliseconds: config.ackTimeoutMs),
    maxRetries: config.maxRetries,
  );

  final endpointA = TransportEndpoint(
    name: 'A',
    link: ScopedTransportLink(endpointId: 'A', link: link),
    config: transportConfig,
    logger: config.verbose ? _logger : null,
  );
  final endpointB = TransportEndpoint(
    name: 'B',
    link: ScopedTransportLink(endpointId: 'B', link: link),
    config: transportConfig,
    logger: config.verbose ? _logger : null,
  );

  link.register('A', endpointA.handlePacket);
  link.register('B', endpointB.handlePacket);

  _printHeader(config, transportConfig);

  for (var i = 0; i < config.iterations; i++) {
    for (final size in config.payloadSizes) {
      final payload = _makePayload(size, rng);
      final retransmitBefore = endpointA.stats.retransmissions;
      final result = await _runOnce(
        sender: endpointA,
        receiver: endpointB,
        payload: payload,
        receiveTimeout: Duration(milliseconds: config.receiveTimeoutMs),
      );

      final chunks = _chunkCount(size, transportConfig.maxPayload);
      final retransmits = endpointA.stats.retransmissions - retransmitBefore;
      final label = result.ok ? 'OK' : 'FAIL';
      final elapsed = result.elapsed.inMilliseconds;
      print(
        'A->B ${size} bytes (chunks=$chunks): $label in ${elapsed}ms '
        '(retransmits=$retransmits)',
      );
    }
  }

  _printStats(endpointA, endpointB, link);
}

void _printUsage() {
  print('Transport harness');
  print('Usage: dart run --no-pub tool/transport_harness.dart [options]');
  print('');
  print('Options:');
  print('  --drop=0.0            Drop rate for both directions');
  print('  --delay-ms=0          Fixed one-way delay in ms');
  print('  --seed=1              RNG seed');
  print('  --sizes=1024,5120     Payload sizes in bytes');
  print('  --iterations=1        Repeat each size');
  print('  --ack-timeout-ms=250  ACK timeout in ms');
  print('  --retries=5           Max retries per packet');
  print('  --max-payload=176     Transport payload size');
  print('  --max-message=65536   Max reassembled message size');
  print('  --receive-timeout=2000 Receiver wait timeout in ms');
  print('  --verbose             Log transport events');
  print('  --help                Show this help');
}

void _printHeader(HarnessConfig config, TransportConfig transport) {
  print('Transport harness');
  print(
    'sizes=${config.payloadSizes.join(',')} drop=${config.dropRate} '
    'delayMs=${config.delayMs} seed=${config.seed} iterations=${config.iterations}',
  );
  print(
    'ackTimeoutMs=${config.ackTimeoutMs} retries=${config.maxRetries} '
    'maxPayload=${transport.maxPayload} maxMessage=${transport.maxMessageBytes}',
  );
}

void _printStats(
  TransportEndpoint endpointA,
  TransportEndpoint endpointB,
  MockDuplexLink link,
) {
  final a = endpointA.stats;
  final b = endpointB.stats;
  print('');
  print(
    'Stats A: sent=${a.packetsSent} recv=${a.packetsReceived} '
    'retransmits=${a.retransmissions} dup=${a.duplicatePackets} '
    'protoErr=${a.protocolErrors} ackTimeouts=${a.ackTimeouts}',
  );
  print(
    'Stats B: sent=${b.packetsSent} recv=${b.packetsReceived} '
    'retransmits=${b.retransmissions} dup=${b.duplicatePackets} '
    'protoErr=${b.protocolErrors} ackTimeouts=${b.ackTimeouts}',
  );
  print(
    'Link: sent=${link.stats.sent} delivered=${link.stats.delivered} '
    'dropped=${link.stats.dropped}',
  );
}

void _logger(String message) {
  final stamp = DateTime.now().toIso8601String();
  print('$stamp $message');
}

Future<_RunResult> _runOnce({
  required TransportEndpoint sender,
  required TransportEndpoint receiver,
  required Uint8List payload,
  required Duration receiveTimeout,
}) async {
  final completer = Completer<Uint8List>();
  late StreamSubscription<Uint8List> sub;
  sub = receiver.messages.listen((data) {
    if (!completer.isCompleted) {
      completer.complete(Uint8List.fromList(data));
      sub.cancel();
    }
  });

  final start = DateTime.now();
  var ok = false;
  try {
    await sender.sendMessage(payload);
    final received = await completer.future.timeout(receiveTimeout);
    ok = _bytesEqual(payload, received);
  } on TimeoutException {
    ok = false;
  } catch (_) {
    ok = false;
  } finally {
    await sub.cancel();
  }

  return _RunResult(ok, DateTime.now().difference(start));
}

Uint8List _makePayload(int size, Random rng) {
  final bytes = Uint8List(size);
  for (var i = 0; i < size; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return bytes;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

int _chunkCount(int size, int maxPayload) {
  if (size == 0) {
    return 1;
  }
  return (size + maxPayload - 1) ~/ maxPayload;
}

class _RunResult {
  _RunResult(this.ok, this.elapsed);

  final bool ok;
  final Duration elapsed;
}

class LinkStats {
  int sent = 0;
  int delivered = 0;
  int dropped = 0;
  int sentFromA = 0;
  int sentFromB = 0;
  int droppedFromA = 0;
  int droppedFromB = 0;
}

class MockDuplexLink implements DirectedTransportLink {
  MockDuplexLink({
    required this.endpointA,
    required this.endpointB,
    required double dropRate,
    required Duration delay,
    required Random rng,
  }) : _dropRate = dropRate,
       _delay = delay,
       _rng = rng;

  final String endpointA;
  final String endpointB;
  final double _dropRate;
  final Duration _delay;
  final Random _rng;

  final Map<String, void Function(Uint8List)> _receivers =
      <String, void Function(Uint8List)>{};

  final LinkStats stats = LinkStats();

  void register(String id, void Function(Uint8List) onReceive) {
    _receivers[id] = onReceive;
  }

  @override
  Future<void> sendFrom(String from, Uint8List bytes) async {
    final to = _other(from);
    if (to == null) {
      return;
    }

    stats.sent++;
    if (from == endpointA) {
      stats.sentFromA++;
    } else if (from == endpointB) {
      stats.sentFromB++;
    }

    if (_rng.nextDouble() < _dropRate) {
      stats.dropped++;
      if (from == endpointA) {
        stats.droppedFromA++;
      } else if (from == endpointB) {
        stats.droppedFromB++;
      }
      return;
    }

    if (_delay == Duration.zero) {
      _deliver(to, bytes);
    } else {
      Future<void>.delayed(_delay, () => _deliver(to, bytes));
    }
  }

  String? _other(String from) {
    if (from == endpointA) {
      return endpointB;
    }
    if (from == endpointB) {
      return endpointA;
    }
    return null;
  }

  void _deliver(String to, Uint8List bytes) {
    final receiver = _receivers[to];
    if (receiver == null) {
      return;
    }
    stats.delivered++;
    receiver(bytes);
  }
}

class HarnessConfig {
  HarnessConfig({
    required this.dropRate,
    required this.delayMs,
    required this.seed,
    required this.payloadSizes,
    required this.iterations,
    required this.ackTimeoutMs,
    required this.maxRetries,
    required this.maxPayload,
    required this.maxMessageBytes,
    required this.receiveTimeoutMs,
    required this.verbose,
    required this.showHelp,
  });

  final double dropRate;
  final int delayMs;
  final int seed;
  final List<int> payloadSizes;
  final int iterations;
  final int ackTimeoutMs;
  final int maxRetries;
  final int maxPayload;
  final int maxMessageBytes;
  final int receiveTimeoutMs;
  final bool verbose;
  final bool showHelp;

  factory HarnessConfig.fromArgs(List<String> args) {
    var dropRate = 0.0;
    var delayMs = 0;
    var seed = 1;
    var payloadSizes = <int>[1024, 5120, 10240];
    var iterations = 1;
    var ackTimeoutMs = 250;
    var maxRetries = 5;
    var maxPayload = 176;
    var maxMessageBytes = 64 * 1024;
    var receiveTimeoutMs = 2000;
    var verbose = false;
    var showHelp = false;

    for (final arg in args) {
      if (arg == '--verbose') {
        verbose = true;
      } else if (arg == '--help' || arg == '-h') {
        showHelp = true;
      } else if (arg.startsWith('--drop=')) {
        dropRate = double.parse(arg.split('=').last);
      } else if (arg.startsWith('--delay-ms=')) {
        delayMs = int.parse(arg.split('=').last);
      } else if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.split('=').last);
      } else if (arg.startsWith('--sizes=')) {
        payloadSizes = arg
            .split('=')
            .last
            .split(',')
            .where((value) => value.trim().isNotEmpty)
            .map(int.parse)
            .toList();
      } else if (arg.startsWith('--iterations=')) {
        iterations = int.parse(arg.split('=').last);
      } else if (arg.startsWith('--ack-timeout-ms=')) {
        ackTimeoutMs = int.parse(arg.split('=').last);
      } else if (arg.startsWith('--retries=')) {
        maxRetries = int.parse(arg.split('=').last);
      } else if (arg.startsWith('--max-payload=')) {
        maxPayload = int.parse(arg.split('=').last);
      } else if (arg.startsWith('--max-message=')) {
        maxMessageBytes = int.parse(arg.split('=').last);
      } else if (arg.startsWith('--receive-timeout=')) {
        receiveTimeoutMs = int.parse(arg.split('=').last);
      }
    }

    return HarnessConfig(
      dropRate: dropRate,
      delayMs: delayMs,
      seed: seed,
      payloadSizes: payloadSizes,
      iterations: iterations,
      ackTimeoutMs: ackTimeoutMs,
      maxRetries: maxRetries,
      maxPayload: maxPayload,
      maxMessageBytes: maxMessageBytes,
      receiveTimeoutMs: receiveTimeoutMs,
      verbose: verbose,
      showHelp: showHelp,
    );
  }
}
