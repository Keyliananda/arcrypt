import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'relay_link.dart';

const String kRelayRealtimePath = '/v1/mailbox/connect';

class RelayRealtimeConfig {
  const RelayRealtimeConfig({
    required this.baseUri,
    required this.mailboxId,
    this.connectTimeout = const Duration(seconds: 8),
    this.subscribeTimeout = const Duration(seconds: 6),
    this.reconnectInitialDelay = const Duration(milliseconds: 500),
    this.reconnectMaxDelay = const Duration(seconds: 8),
    this.jitterFactor = 0.2,
    this.random,
    this.now,
  });

  final Uri baseUri;
  final String mailboxId;
  final Duration connectTimeout;
  final Duration subscribeTimeout;
  final Duration reconnectInitialDelay;
  final Duration reconnectMaxDelay;
  final double jitterFactor;
  final Random? random;
  final DateTime Function()? now;

  Uri get webSocketUri {
    final resolved = baseUri.resolve(kRelayRealtimePath);
    final wsScheme = switch (resolved.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      _ => resolved.scheme,
    };
    return resolved.replace(scheme: wsScheme);
  }
}

class RelayRealtimeUpdate {
  RelayRealtimeUpdate({
    required this.type,
    this.messageId,
    this.isSynthetic = false,
  });

  final String type;
  final String? messageId;
  final bool isSynthetic;
}

class RelayRealtimeClient {
  RelayRealtimeClient({
    required RelayRealtimeConfig config,
    required this.onReady,
    required this.onUpdate,
    this.onError,
    void Function(String message)? logger,
  }) : _config = config,
       _logger = logger;

  final RelayRealtimeConfig _config;
  final Future<void> Function() onReady;
  final Future<void> Function(RelayRealtimeUpdate update) onUpdate;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final void Function(String message)? _logger;

  bool _running = false;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;
  Completer<void>? _reconnectCompleter;
  Completer<void>? _readyCompleter;
  Future<void>? _runLoop;
  int _consecutiveFailures = 0;

  bool get isRunning => _running;

  void start() {
    if (_running) {
      return;
    }
    _running = true;
    _runLoop = _connect();
  }

  Future<void> stop() async {
    _running = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final reconnectCompleter = _reconnectCompleter;
    if (reconnectCompleter != null && !reconnectCompleter.isCompleted) {
      reconnectCompleter.complete();
    }
    _reconnectCompleter = null;
    final socketSub = _socketSub;
    _socketSub = null;
    await socketSub?.cancel();
    final socket = _socket;
    _socket = null;
    await socket?.close(WebSocketStatus.goingAway);
    final runLoop = _runLoop;
    _runLoop = null;
    if (runLoop != null) {
      await runLoop;
    }
  }

  Future<void> requestSync({String reason = 'manual'}) {
    if (!_running) {
      return Future<void>.value();
    }
    return onUpdate(RelayRealtimeUpdate(type: reason, isSynthetic: true));
  }

  Future<void> _connect() async {
    while (_running) {
      try {
        await _connectOnce();
        _consecutiveFailures = 0;
      } catch (error, stackTrace) {
        _consecutiveFailures += 1;
        _log('Realtime connect failed: $error');
        onError?.call(error, stackTrace);
      }

      if (!_running) {
        break;
      }

      final delay = _computeReconnectDelay();
      _log('Realtime reconnect in ${delay.inMilliseconds}ms');
      final completer = Completer<void>();
      _reconnectCompleter = completer;
      _reconnectTimer = Timer(delay, completer.complete);
      await completer.future;
      _reconnectTimer = null;
      _reconnectCompleter = null;
    }
  }

  Future<void> _connectOnce() async {
    final socket = await WebSocket.connect(
      _config.webSocketUri.toString(),
    ).timeout(_config.connectTimeout);
    _socket = socket;
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;

    _socketSub = socket.listen(
      (dynamic raw) {
        try {
          _handleMessage(raw);
        } catch (error, stackTrace) {
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(error, stackTrace);
          } else {
            onError?.call(error, stackTrace);
          }
          unawaited(socket.close(WebSocketStatus.policyViolation));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(error, stackTrace);
        } else {
          onError?.call(error, stackTrace);
        }
      },
      onDone: () {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(
            RelayLinkException('realtime socket closed before ready'),
          );
        }
      },
      cancelOnError: false,
    );

    socket.add(jsonEncode(_buildSubscribePayload()));
    await readyCompleter.future.timeout(_config.subscribeTimeout);
    _consecutiveFailures = 0;
    await onReady();

    final doneCompleter = Completer<void>();
    socket.done
        .then<void>((_) {
          if (!doneCompleter.isCompleted) {
            doneCompleter.complete();
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!doneCompleter.isCompleted) {
            doneCompleter.completeError(error, stackTrace);
          }
          onError?.call(error, stackTrace);
        });

    try {
      await doneCompleter.future;
    } finally {
      await _socketSub?.cancel();
      _socketSub = null;
      _socket = null;
      _readyCompleter = null;
    }
  }

  void _handleMessage(dynamic raw) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw RelayLinkException('realtime response is not a JSON object');
    }

    final type = _readRequiredString(decoded, 'type');
    switch (type) {
      case 'ready':
        _log('Realtime subscribed');
        _readyCompleter?.complete();
        return;
      case 'mailbox_update':
        unawaited(
          onUpdate(
            RelayRealtimeUpdate(
              type: type,
              messageId: _readOptionalString(decoded['message_id']),
            ),
          ),
        );
        return;
      case 'error':
        final errorCode = _readOptionalString(decoded['error']) ?? 'unknown';
        final error = RelayLinkException(
          'realtime subscription failed',
          errorCode: errorCode,
          details: _readOptionalMap(decoded['details']),
        );
        if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!.completeError(error);
          return;
        }
        throw error;
      case 'pong':
        return;
      default:
        _log('Realtime ignored message type=$type');
    }
  }

  Map<String, dynamic> _buildSubscribePayload() {
    final ts = _now().millisecondsSinceEpoch ~/ 1000;
    final nonce = _makeNonce();
    final unsigned = <String, dynamic>{
      'type': 'subscribe',
      'mailbox_id': _config.mailboxId,
      'ts': ts,
      'nonce': nonce,
    };
    final proof = computeMailboxProof(
      mailboxId: _config.mailboxId,
      method: 'WS',
      path: kRelayRealtimePath,
      ts: ts,
      nonce: nonce,
      bodyWithoutProof: unsigned,
    );
    return <String, dynamic>{...unsigned, 'proof': proof};
  }

  Duration _computeReconnectDelay() {
    final base = _config.reconnectInitialDelay.inMilliseconds;
    final max = _config.reconnectMaxDelay.inMilliseconds;
    final exponent = (_consecutiveFailures - 1).clamp(0, 16);
    var delayMs = base * (1 << exponent);
    if (delayMs > max) {
      delayMs = max;
    }
    return computeJitteredInterval(
      baseInterval: Duration(milliseconds: delayMs),
      jitterFactor: _config.jitterFactor,
      random: _random(),
    );
  }

  DateTime _now() {
    final now = _config.now;
    if (now != null) {
      return now();
    }
    return DateTime.now().toUtc();
  }

  String _makeNonce() {
    final random = _random();
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Random _random() => _config.random ?? Random.secure();

  void _log(String message) {
    _logger?.call('[RelayRealtimeClient] $message');
  }
}

String _readRequiredString(Map<String, dynamic> json, String key) {
  final value = _readOptionalString(json[key]);
  if (value != null) {
    return value;
  }
  throw RelayLinkException('missing string field: $key');
}

String? _readOptionalString(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

Map<String, dynamic>? _readOptionalMap(Object? value) {
  return value is Map<String, dynamic> ? value : null;
}
