import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hive/hive.dart';

import 'relay_link.dart';

const String kRelayOutboxBox = 'relay_outbox';
const int kRelayOutboxEntryTypeId = 26;

class RelayOutboxStatus {
  const RelayOutboxStatus._();

  static const int pending = 0;
  static const int sent = 1;
  static const int failed = 2;
}

class RelayOutboxEntry {
  RelayOutboxEntry({
    required this.clientMsgId,
    required Uint8List ciphertext,
    required this.status,
    required this.attempts,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.sentAtMs,
    this.relayMessageId,
    this.relayExpiresAtMs,
    this.lastError,
  }) : ciphertext = Uint8List.fromList(ciphertext);

  final String clientMsgId;
  final Uint8List ciphertext;
  final int status;
  final int attempts;
  final int createdAtMs;
  final int updatedAtMs;
  final int? sentAtMs;
  final String? relayMessageId;
  final int? relayExpiresAtMs;
  final String? lastError;

  RelayOutboxEntry copyWith({
    String? clientMsgId,
    Uint8List? ciphertext,
    int? status,
    int? attempts,
    int? createdAtMs,
    int? updatedAtMs,
    int? sentAtMs,
    bool clearSentAtMs = false,
    String? relayMessageId,
    bool clearRelayMessageId = false,
    int? relayExpiresAtMs,
    bool clearRelayExpiresAtMs = false,
    String? lastError,
    bool clearLastError = false,
  }) {
    return RelayOutboxEntry(
      clientMsgId: clientMsgId ?? this.clientMsgId,
      ciphertext: ciphertext ?? this.ciphertext,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      sentAtMs: clearSentAtMs ? null : (sentAtMs ?? this.sentAtMs),
      relayMessageId: clearRelayMessageId
          ? null
          : (relayMessageId ?? this.relayMessageId),
      relayExpiresAtMs: clearRelayExpiresAtMs
          ? null
          : (relayExpiresAtMs ?? this.relayExpiresAtMs),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}

class RelayOutboxEntryAdapter extends TypeAdapter<RelayOutboxEntry> {
  @override
  final int typeId = kRelayOutboxEntryTypeId;

  @override
  RelayOutboxEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return RelayOutboxEntry(
      clientMsgId: fields[0] as String? ?? '',
      ciphertext: (fields[1] as Uint8List?) ?? Uint8List(0),
      status: fields[2] as int? ?? RelayOutboxStatus.pending,
      attempts: fields[3] as int? ?? 0,
      createdAtMs: fields[4] as int? ?? 0,
      updatedAtMs: fields[5] as int? ?? 0,
      sentAtMs: fields[6] as int?,
      relayMessageId: fields[7] as String?,
      relayExpiresAtMs: fields[8] as int?,
      lastError: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, RelayOutboxEntry obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.clientMsgId)
      ..writeByte(1)
      ..write(obj.ciphertext)
      ..writeByte(2)
      ..write(obj.status)
      ..writeByte(3)
      ..write(obj.attempts)
      ..writeByte(4)
      ..write(obj.createdAtMs)
      ..writeByte(5)
      ..write(obj.updatedAtMs)
      ..writeByte(6)
      ..write(obj.sentAtMs)
      ..writeByte(7)
      ..write(obj.relayMessageId)
      ..writeByte(8)
      ..write(obj.relayExpiresAtMs)
      ..writeByte(9)
      ..write(obj.lastError);
  }
}

void registerRelayOutboxAdapter() {
  if (!Hive.isAdapterRegistered(kRelayOutboxEntryTypeId)) {
    Hive.registerAdapter(RelayOutboxEntryAdapter());
  }
}

abstract class RelayOutboxStore {
  Future<RelayOutboxEntry?> getByClientMsgId(String clientMsgId);
  Future<List<RelayOutboxEntry>> listPending({required int limit});
  Future<void> put(RelayOutboxEntry entry);
  Future<void> close();
}

class HiveRelayOutboxStore implements RelayOutboxStore {
  HiveRelayOutboxStore._(this._box);

  final Box<RelayOutboxEntry> _box;

  static Future<HiveRelayOutboxStore> open({
    String boxName = kRelayOutboxBox,
  }) async {
    registerRelayOutboxAdapter();
    final box = await Hive.openBox<RelayOutboxEntry>(boxName);
    return HiveRelayOutboxStore._(box);
  }

  @override
  Future<RelayOutboxEntry?> getByClientMsgId(String clientMsgId) async {
    final entry = _box.get(clientMsgId);
    if (entry == null) {
      return null;
    }
    return entry.copyWith();
  }

  @override
  Future<List<RelayOutboxEntry>> listPending({required int limit}) async {
    final pending = _box.values
        .where((entry) => entry.status == RelayOutboxStatus.pending)
        .map((entry) => entry.copyWith())
        .toList(growable: false);
    pending.sort((a, b) {
      final byCreated = a.createdAtMs.compareTo(b.createdAtMs);
      if (byCreated != 0) {
        return byCreated;
      }
      return a.clientMsgId.compareTo(b.clientMsgId);
    });
    if (pending.length <= limit) {
      return pending;
    }
    return pending.sublist(0, limit);
  }

  @override
  Future<void> put(RelayOutboxEntry entry) {
    return _box.put(entry.clientMsgId, entry.copyWith());
  }

  @override
  Future<void> close() {
    return _box.close();
  }
}

typedef RelayOutboxSender =
    Future<RelayPushResult> Function({
      required Uint8List ciphertext,
      required String clientMsgId,
    });

class RelayOutboxFlushResult {
  RelayOutboxFlushResult({
    required this.processed,
    required this.sent,
    required this.retryScheduled,
    required this.failed,
  });

  final int processed;
  final int sent;
  final int retryScheduled;
  final int failed;
}

class RelayOutboxQueue {
  RelayOutboxQueue({
    required RelayOutboxStore store,
    required RelayOutboxSender sender,
    DateTime Function()? now,
    Random? random,
  }) : _store = store,
       _sender = sender,
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final RelayOutboxStore _store;
  final RelayOutboxSender _sender;
  final DateTime Function() _now;
  final Random _random;

  Future<RelayOutboxEntry> enqueue({
    required Uint8List ciphertext,
    String? clientMsgId,
  }) async {
    final resolvedClientMsgId = clientMsgId ?? _newClientMsgId();
    if (!_isValidClientMsgId(resolvedClientMsgId)) {
      throw ArgumentError.value(
        resolvedClientMsgId,
        'clientMsgId',
        'must be 1..128 chars',
      );
    }

    final existing = await _store.getByClientMsgId(resolvedClientMsgId);
    if (existing != null) {
      if (!_bytesEqual(existing.ciphertext, ciphertext)) {
        throw StateError('client_msg_id already used for different ciphertext');
      }
      return existing;
    }

    final nowMs = _now().millisecondsSinceEpoch;
    final entry = RelayOutboxEntry(
      clientMsgId: resolvedClientMsgId,
      ciphertext: ciphertext,
      status: RelayOutboxStatus.pending,
      attempts: 0,
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
    );
    await _store.put(entry);
    return entry;
  }

  Future<RelayOutboxFlushResult> flushPending({int limit = 50}) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be >= 1');
    }

    final entries = await _store.listPending(limit: limit);
    var sent = 0;
    var retryScheduled = 0;
    var failed = 0;

    for (final entry in entries) {
      final beforeSend = entry.copyWith(
        attempts: entry.attempts + 1,
        updatedAtMs: _now().millisecondsSinceEpoch,
        clearLastError: true,
      );
      await _store.put(beforeSend);

      try {
        final result = await _sender(
          ciphertext: beforeSend.ciphertext,
          clientMsgId: beforeSend.clientMsgId,
        );
        await _store.put(
          beforeSend.copyWith(
            status: RelayOutboxStatus.sent,
            sentAtMs: _now().millisecondsSinceEpoch,
            relayMessageId: result.messageId,
            relayExpiresAtMs: result.expiresAt?.millisecondsSinceEpoch,
            clearLastError: true,
          ),
        );
        sent++;
      } catch (error) {
        final retryable = error is RelayLinkException && error.retryable;
        await _store.put(
          beforeSend.copyWith(
            status: retryable
                ? RelayOutboxStatus.pending
                : RelayOutboxStatus.failed,
            lastError: error.toString(),
            updatedAtMs: _now().millisecondsSinceEpoch,
          ),
        );
        if (retryable) {
          retryScheduled++;
        } else {
          failed++;
        }
      }
    }

    return RelayOutboxFlushResult(
      processed: entries.length,
      sent: sent,
      retryScheduled: retryScheduled,
      failed: failed,
    );
  }

  String _newClientMsgId() {
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

bool _isValidClientMsgId(String value) {
  return value.isNotEmpty && value.length <= 128;
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
