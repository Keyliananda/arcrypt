import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'relay_inbox.dart';
import 'transport.dart';

class RelayLinkConfig {
  const RelayLinkConfig({
    required this.baseUri,
    this.requestTimeout = const Duration(seconds: 5),
    this.maxRetries = 3,
    this.initialBackoff = const Duration(milliseconds: 250),
    this.maxBackoff = const Duration(seconds: 3),
    this.jitterFactor = 0.2,
    this.defaultPullLimit = 50,
    this.maxCiphertextBytes = 64 * 1024,
    this.random,
    this.now,
  });

  final Uri baseUri;
  final Duration requestTimeout;
  final int maxRetries;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final double jitterFactor;
  final int defaultPullLimit;
  final int maxCiphertextBytes;
  final Random? random;
  final DateTime Function()? now;
}

class RelayLinkException implements Exception {
  RelayLinkException(
    this.message, {
    this.statusCode,
    this.errorCode,
    this.details,
    this.retryable = false,
    this.cause,
  });

  final String message;
  final int? statusCode;
  final String? errorCode;
  final Map<String, dynamic>? details;
  final bool retryable;
  final Object? cause;

  @override
  String toString() {
    final parts = <String>[
      'RelayLinkException: $message',
      if (statusCode != null) 'status=$statusCode',
      if (errorCode != null) 'error=$errorCode',
      if (retryable) 'retryable=true',
    ];
    return parts.join(' ');
  }
}

class RelayPushResult {
  RelayPushResult({
    required this.messageId,
    required this.status,
    required this.expiresAt,
  });

  final String messageId;
  final String status;
  final DateTime? expiresAt;
}

class RelayPulledMessage {
  RelayPulledMessage({
    required this.messageId,
    required this.ciphertext,
    required this.createdAt,
    required this.expiresAt,
    required this.sizeBytes,
  });

  final String messageId;
  final Uint8List ciphertext;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final int? sizeBytes;
}

class RelayPullResult {
  RelayPullResult({
    required this.messages,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<RelayPulledMessage> messages;
  final String? nextCursor;
  final bool hasMore;
}

class RelayAckResult {
  RelayAckResult({
    required this.acked,
    required this.unknown,
    required this.alreadyAcked,
  });

  final List<String> acked;
  final List<String> unknown;
  final List<String> alreadyAcked;
}

class RelayPollResult {
  RelayPollResult({required this.pull, this.ack});

  final RelayPullResult pull;
  final RelayAckResult? ack;
}

class RelayMailboxHttpClient {
  RelayMailboxHttpClient({
    required RelayLinkConfig config,
    void Function(String message)? logger,
    HttpClient? httpClient,
  }) : _config = config,
       _logger = logger,
       _httpClient = httpClient ?? HttpClient();

  final RelayLinkConfig _config;
  final void Function(String message)? _logger;
  final HttpClient _httpClient;

  Future<RelayPushResult> push({
    required String mailboxId,
    required Uint8List ciphertext,
    int? expiresInSec,
    String? clientMsgId,
    Uint8List? padding,
  }) async {
    if (ciphertext.length > _config.maxCiphertextBytes) {
      throw RelayLinkException(
        'ciphertext exceeds maxCiphertextBytes',
        details: <String, dynamic>{
          'maxCiphertextBytes': _config.maxCiphertextBytes,
        },
      );
    }

    final body = <String, dynamic>{
      'mailbox_id': mailboxId,
      'ciphertext': base64Encode(ciphertext),
      if (expiresInSec != null) 'expires_in_sec': expiresInSec,
      if (clientMsgId != null) 'client_msg_id': clientMsgId,
      if (padding != null) 'padding': base64Encode(padding),
    };
    final json = await _postSigned(
      path: '/v1/mailbox/push',
      mailboxId: mailboxId,
      body: body,
      expectedStatuses: const <int>{202},
    );
    return RelayPushResult(
      messageId: _readRequiredString(json, 'message_id'),
      status: _readRequiredString(json, 'status'),
      expiresAt: _readOptionalDateTime(json['expires_at']),
    );
  }

  Future<RelayPullResult> pull({
    required String mailboxId,
    String? cursor,
    int? limit,
  }) async {
    final body = <String, dynamic>{
      'mailbox_id': mailboxId,
      'cursor': cursor,
      'limit': limit ?? _config.defaultPullLimit,
    };
    final json = await _postSigned(
      path: '/v1/mailbox/pull',
      mailboxId: mailboxId,
      body: body,
      expectedStatuses: const <int>{200},
    );

    final messagesRaw = json['messages'];
    if (messagesRaw is! List) {
      throw RelayLinkException('relay pull response missing messages list');
    }

    final messages = <RelayPulledMessage>[];
    for (final item in messagesRaw) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final ciphertextB64 = _readRequiredString(item, 'ciphertext');
      Uint8List decoded;
      try {
        decoded = Uint8List.fromList(base64Decode(ciphertextB64));
      } on FormatException {
        throw RelayLinkException('invalid base64 ciphertext in pull response');
      }
      messages.add(
        RelayPulledMessage(
          messageId: _readRequiredString(item, 'message_id'),
          ciphertext: decoded,
          createdAt: _readOptionalDateTime(item['created_at']),
          expiresAt: _readOptionalDateTime(item['expires_at']),
          sizeBytes: _readOptionalInt(item['size_bytes']),
        ),
      );
    }

    return RelayPullResult(
      messages: messages,
      nextCursor: _readOptionalString(json['next_cursor']),
      hasMore: json['has_more'] == true,
    );
  }

  Future<RelayAckResult> ack({
    required String mailboxId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) {
      return RelayAckResult(
        acked: const <String>[],
        unknown: const <String>[],
        alreadyAcked: const <String>[],
      );
    }

    final body = <String, dynamic>{
      'mailbox_id': mailboxId,
      'message_ids': messageIds,
    };
    final json = await _postSigned(
      path: '/v1/mailbox/ack',
      mailboxId: mailboxId,
      body: body,
      expectedStatuses: const <int>{200},
    );

    return RelayAckResult(
      acked: _readStringList(json['acked']),
      unknown: _readStringList(json['unknown']),
      alreadyAcked: _readStringList(json['already_acked']),
    );
  }

  void close({bool force = false}) {
    _httpClient.close(force: force);
  }

  Future<Map<String, dynamic>> _postSigned({
    required String path,
    required String mailboxId,
    required Map<String, dynamic> body,
    required Set<int> expectedStatuses,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final ts = _now().millisecondsSinceEpoch ~/ 1000;
      final nonce = _makeNonce();
      final unsigned = <String, dynamic>{...body, 'ts': ts, 'nonce': nonce};
      final proof = computeMailboxProof(
        mailboxId: mailboxId,
        method: 'POST',
        path: path,
        ts: ts,
        nonce: nonce,
        bodyWithoutProof: unsigned,
      );
      final signed = <String, dynamic>{...unsigned, 'proof': proof};

      _log('POST $path attempt=$attempt');
      try {
        final response = await _postJson(path: path, body: signed);
        if (expectedStatuses.contains(response.statusCode)) {
          final ok = response.json['ok'];
          if (ok != true) {
            throw RelayLinkException(
              'relay response ok=false',
              statusCode: response.statusCode,
              errorCode: _readOptionalString(response.json['error']),
              details: _readOptionalMap(response.json['details']),
            );
          }
          return response.json;
        }

        final errorCode = _readOptionalString(response.json['error']);
        final retryable = _isRetryableStatus(response.statusCode);
        if (!retryable || attempt > _config.maxRetries) {
          throw RelayLinkException(
            'relay request failed',
            statusCode: response.statusCode,
            errorCode: errorCode,
            details: _readOptionalMap(response.json['details']),
            retryable: retryable,
          );
        }
      } on TimeoutException catch (e) {
        if (attempt > _config.maxRetries) {
          throw RelayLinkException(
            'relay request timeout',
            retryable: true,
            cause: e,
          );
        }
      } on SocketException catch (e) {
        if (attempt > _config.maxRetries) {
          throw RelayLinkException(
            'relay socket error',
            retryable: true,
            cause: e,
          );
        }
      } on HttpException catch (e) {
        if (attempt > _config.maxRetries) {
          throw RelayLinkException(
            'relay http error',
            retryable: true,
            cause: e,
          );
        }
      }

      await Future<void>.delayed(_computeBackoff(attempt));
    }
  }

  Future<_JsonResponse> _postJson({
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final uri = _config.baseUri.resolve(path);
    final request = await _httpClient
        .postUrl(uri)
        .timeout(_config.requestTimeout);
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));

    final response = await request.close().timeout(_config.requestTimeout);
    final text = await response.transform(utf8.decoder).join();
    Map<String, dynamic> json;
    if (text.isEmpty) {
      json = <String, dynamic>{};
    } else {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw RelayLinkException('relay response is not a JSON object');
      }
      json = decoded;
    }
    return _JsonResponse(statusCode: response.statusCode, json: json);
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 429 || statusCode >= 500;
  }

  Duration _computeBackoff(int attempt) {
    final exponent = attempt - 1;
    final baseMs =
        _config.initialBackoff.inMilliseconds * (1 << exponent.clamp(0, 16));
    var clampedMs = baseMs;
    if (clampedMs > _config.maxBackoff.inMilliseconds) {
      clampedMs = _config.maxBackoff.inMilliseconds;
    }
    final jitterRange = (clampedMs * _config.jitterFactor).round();
    if (jitterRange <= 0) {
      return Duration(milliseconds: clampedMs);
    }
    final random = _random();
    final offset = random.nextInt(jitterRange * 2 + 1) - jitterRange;
    return Duration(milliseconds: clampedMs + offset);
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
    _logger?.call('[RelayMailboxHttpClient] $message');
  }
}

class RelayLink implements TransportLink {
  RelayLink({
    required RelayMailboxHttpClient client,
    required this.outboundMailboxId,
    required this.inboundMailboxId,
    this.onInboundCiphertext,
    this.inboxQueue,
    this.defaultAutoAck = true,
    this.defaultPullLimit,
    Random? random,
  }) : _client = client,
       _random = random ?? Random.secure();

  final RelayMailboxHttpClient _client;
  final String outboundMailboxId;
  final String inboundMailboxId;
  final void Function(Uint8List bytes)? onInboundCiphertext;
  final RelayInboxQueue? inboxQueue;
  final bool defaultAutoAck;
  final int? defaultPullLimit;
  final Random _random;

  @override
  Future<void> send(Uint8List bytes) async {
    await pushCiphertext(bytes);
  }

  Future<RelayPushResult> pushCiphertext(
    Uint8List bytes, {
    String? clientMsgId,
    int? expiresInSec,
    Uint8List? padding,
  }) {
    return _client.push(
      mailboxId: outboundMailboxId,
      ciphertext: bytes,
      expiresInSec: expiresInSec,
      clientMsgId: clientMsgId ?? _nextClientMsgId(),
      padding: padding,
    );
  }

  Future<RelayPullResult> pull({String? cursor, int? limit}) {
    return _client.pull(
      mailboxId: inboundMailboxId,
      cursor: cursor,
      limit: limit ?? defaultPullLimit,
    );
  }

  Future<RelayAckResult> ack({required List<String> messageIds}) {
    return _client.ack(mailboxId: inboundMailboxId, messageIds: messageIds);
  }

  Future<RelayPollResult> pollOnce({
    String? cursor,
    int? limit,
    bool? autoAck,
  }) async {
    final pulled = await pull(cursor: cursor, limit: limit);
    final inbox = inboxQueue;
    if (inbox == null) {
      for (final message in pulled.messages) {
        onInboundCiphertext?.call(Uint8List.fromList(message.ciphertext));
      }
    } else {
      await inbox.enqueuePulled(
        messages: pulled.messages
            .map(
              (message) => RelayInboxIncomingMessage(
                messageId: message.messageId,
                ciphertext: message.ciphertext,
                createdAt: message.createdAt,
                expiresAt: message.expiresAt,
                sizeBytes: message.sizeBytes,
              ),
            )
            .toList(growable: false),
      );
      await inbox.drainPending(
        limit: limit ?? defaultPullLimit ?? 50,
        onEntry: (entry) async {
          onInboundCiphertext?.call(Uint8List.fromList(entry.ciphertext));
        },
      );
    }

    RelayAckResult? ackResult;
    final shouldAck = autoAck ?? defaultAutoAck;
    if (shouldAck && pulled.messages.isNotEmpty) {
      ackResult = await ack(
        messageIds: pulled.messages.map((m) => m.messageId).toList(),
      );
    }
    return RelayPollResult(pull: pulled, ack: ackResult);
  }

  void close({bool force = false}) {
    _client.close(force: force);
  }

  String _nextClientMsgId() {
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class _JsonResponse {
  _JsonResponse({required this.statusCode, required this.json});

  final int statusCode;
  final Map<String, dynamic> json;
}

String computeMailboxProof({
  required String mailboxId,
  required String method,
  required String path,
  required int ts,
  required String nonce,
  required Map<String, dynamic> bodyWithoutProof,
}) {
  final bodySha = sha256Hex(stableJsonEncode(bodyWithoutProof));
  final canonical = '${method.toUpperCase()}\n$path\n$ts\n$nonce\n$bodySha';
  final mac = Hmac(sha256, utf8.encode(mailboxId));
  return mac.convert(utf8.encode(canonical)).toString();
}

String stableJsonEncode(Object? value) {
  return jsonEncode(_normalizeStable(value));
}

String sha256Hex(String value) {
  return sha256.convert(utf8.encode(value)).toString();
}

Object? _normalizeStable(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return value.map(_normalizeStable).toList(growable: false);
  }
  if (value is Map) {
    final normalized = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError('stable json map keys must be strings');
      }
      normalized[entry.key as String] = _normalizeStable(entry.value);
    }
    return normalized;
  }
  throw ArgumentError('unsupported json type: ${value.runtimeType}');
}

String _readRequiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw RelayLinkException('missing string field: $key');
}

String? _readOptionalString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

int? _readOptionalInt(Object? value) {
  if (value is int) {
    return value;
  }
  return null;
}

DateTime? _readOptionalDateTime(Object? value) {
  final text = _readOptionalString(value);
  if (text == null) {
    return null;
  }
  return DateTime.tryParse(text)?.toUtc();
}

Map<String, dynamic>? _readOptionalMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  return null;
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return <String>[];
  }
  return value.whereType<String>().toList(growable: false);
}
