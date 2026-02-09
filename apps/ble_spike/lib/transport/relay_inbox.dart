import 'dart:typed_data';

import 'package:hive/hive.dart';

const String kRelayInboxBox = 'relay_inbox';
const int kRelayInboxEntryTypeId = 27;

class RelayInboxStatus {
  const RelayInboxStatus._();

  static const int pending = 0;
  static const int delivered = 1;
}

class RelayInboxEntry {
  RelayInboxEntry({
    required this.messageId,
    required Uint8List ciphertext,
    required this.status,
    required this.firstSeenAtMs,
    required this.updatedAtMs,
    this.createdAtMs,
    this.expiresAtMs,
    this.sizeBytes,
    this.deliveredAtMs,
  }) : ciphertext = Uint8List.fromList(ciphertext);

  final String messageId;
  final Uint8List ciphertext;
  final int status;
  final int firstSeenAtMs;
  final int updatedAtMs;
  final int? createdAtMs;
  final int? expiresAtMs;
  final int? sizeBytes;
  final int? deliveredAtMs;

  RelayInboxEntry copyWith({
    String? messageId,
    Uint8List? ciphertext,
    int? status,
    int? firstSeenAtMs,
    int? updatedAtMs,
    int? createdAtMs,
    bool clearCreatedAtMs = false,
    int? expiresAtMs,
    bool clearExpiresAtMs = false,
    int? sizeBytes,
    bool clearSizeBytes = false,
    int? deliveredAtMs,
    bool clearDeliveredAtMs = false,
  }) {
    return RelayInboxEntry(
      messageId: messageId ?? this.messageId,
      ciphertext: ciphertext ?? this.ciphertext,
      status: status ?? this.status,
      firstSeenAtMs: firstSeenAtMs ?? this.firstSeenAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      createdAtMs: clearCreatedAtMs ? null : (createdAtMs ?? this.createdAtMs),
      expiresAtMs: clearExpiresAtMs ? null : (expiresAtMs ?? this.expiresAtMs),
      sizeBytes: clearSizeBytes ? null : (sizeBytes ?? this.sizeBytes),
      deliveredAtMs: clearDeliveredAtMs
          ? null
          : (deliveredAtMs ?? this.deliveredAtMs),
    );
  }
}

class RelayInboxEntryAdapter extends TypeAdapter<RelayInboxEntry> {
  @override
  final int typeId = kRelayInboxEntryTypeId;

  @override
  RelayInboxEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return RelayInboxEntry(
      messageId: fields[0] as String? ?? '',
      ciphertext: (fields[1] as Uint8List?) ?? Uint8List(0),
      status: fields[2] as int? ?? RelayInboxStatus.pending,
      firstSeenAtMs: fields[3] as int? ?? 0,
      updatedAtMs: fields[4] as int? ?? 0,
      createdAtMs: fields[5] as int?,
      expiresAtMs: fields[6] as int?,
      sizeBytes: fields[7] as int?,
      deliveredAtMs: fields[8] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, RelayInboxEntry obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.messageId)
      ..writeByte(1)
      ..write(obj.ciphertext)
      ..writeByte(2)
      ..write(obj.status)
      ..writeByte(3)
      ..write(obj.firstSeenAtMs)
      ..writeByte(4)
      ..write(obj.updatedAtMs)
      ..writeByte(5)
      ..write(obj.createdAtMs)
      ..writeByte(6)
      ..write(obj.expiresAtMs)
      ..writeByte(7)
      ..write(obj.sizeBytes)
      ..writeByte(8)
      ..write(obj.deliveredAtMs);
  }
}

void registerRelayInboxAdapter() {
  if (!Hive.isAdapterRegistered(kRelayInboxEntryTypeId)) {
    Hive.registerAdapter(RelayInboxEntryAdapter());
  }
}

abstract class RelayInboxStore {
  Future<RelayInboxEntry?> getByMessageId(String messageId);
  Future<List<RelayInboxEntry>> listPending({required int limit});
  Future<void> put(RelayInboxEntry entry);
  Future<void> close();
}

class HiveRelayInboxStore implements RelayInboxStore {
  HiveRelayInboxStore._(this._box);

  final Box<RelayInboxEntry> _box;

  static Future<HiveRelayInboxStore> open({
    String boxName = kRelayInboxBox,
  }) async {
    registerRelayInboxAdapter();
    final box = await Hive.openBox<RelayInboxEntry>(boxName);
    return HiveRelayInboxStore._(box);
  }

  @override
  Future<RelayInboxEntry?> getByMessageId(String messageId) async {
    final entry = _box.get(messageId);
    if (entry == null) {
      return null;
    }
    return entry.copyWith();
  }

  @override
  Future<List<RelayInboxEntry>> listPending({required int limit}) async {
    final pending = _box.values
        .where((entry) => entry.status == RelayInboxStatus.pending)
        .map((entry) => entry.copyWith())
        .toList(growable: false);
    pending.sort((a, b) {
      final byFirstSeen = a.firstSeenAtMs.compareTo(b.firstSeenAtMs);
      if (byFirstSeen != 0) {
        return byFirstSeen;
      }
      return a.messageId.compareTo(b.messageId);
    });
    if (pending.length <= limit) {
      return pending;
    }
    return pending.sublist(0, limit);
  }

  @override
  Future<void> put(RelayInboxEntry entry) {
    return _box.put(entry.messageId, entry.copyWith());
  }

  @override
  Future<void> close() {
    return _box.close();
  }
}

class RelayInboxEnqueueResult {
  RelayInboxEnqueueResult({
    required this.processed,
    required this.inserted,
    required this.duplicates,
  });

  final int processed;
  final int inserted;
  final int duplicates;
}

class RelayInboxDrainResult {
  RelayInboxDrainResult({required this.processed, required this.delivered});

  final int processed;
  final int delivered;
}

class RelayInboxIncomingMessage {
  RelayInboxIncomingMessage({
    required this.messageId,
    required Uint8List ciphertext,
    this.createdAt,
    this.expiresAt,
    this.sizeBytes,
  }) : ciphertext = Uint8List.fromList(ciphertext);

  final String messageId;
  final Uint8List ciphertext;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final int? sizeBytes;
}

typedef RelayInboxHandler = Future<void> Function(RelayInboxEntry entry);

class RelayInboxQueue {
  RelayInboxQueue({required RelayInboxStore store, DateTime Function()? now})
    : _store = store,
      _now = now ?? DateTime.now;

  final RelayInboxStore _store;
  final DateTime Function() _now;

  Future<RelayInboxEnqueueResult> enqueuePulled({
    required List<RelayInboxIncomingMessage> messages,
  }) async {
    var inserted = 0;
    var duplicates = 0;
    final nowMs = _now().millisecondsSinceEpoch;

    for (final message in messages) {
      final messageId = message.messageId;
      if (!_isValidMessageId(messageId)) {
        throw ArgumentError.value(
          messageId,
          'message.messageId',
          'must be 1..256 chars',
        );
      }

      final existing = await _store.getByMessageId(messageId);
      if (existing != null) {
        if (!_bytesEqual(existing.ciphertext, message.ciphertext)) {
          throw StateError('message_id already used for different ciphertext');
        }
        duplicates++;
        continue;
      }

      final entry = RelayInboxEntry(
        messageId: messageId,
        ciphertext: message.ciphertext,
        status: RelayInboxStatus.pending,
        firstSeenAtMs: nowMs,
        updatedAtMs: nowMs,
        createdAtMs: message.createdAt?.millisecondsSinceEpoch,
        expiresAtMs: message.expiresAt?.millisecondsSinceEpoch,
        sizeBytes: message.sizeBytes,
      );
      await _store.put(entry);
      inserted++;
    }

    return RelayInboxEnqueueResult(
      processed: messages.length,
      inserted: inserted,
      duplicates: duplicates,
    );
  }

  Future<RelayInboxDrainResult> drainPending({
    required RelayInboxHandler onEntry,
    int limit = 50,
  }) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be >= 1');
    }
    final pending = await _store.listPending(limit: limit);
    var delivered = 0;
    for (final entry in pending) {
      await onEntry(entry.copyWith());
      await _store.put(
        entry.copyWith(
          status: RelayInboxStatus.delivered,
          deliveredAtMs: _now().millisecondsSinceEpoch,
          updatedAtMs: _now().millisecondsSinceEpoch,
        ),
      );
      delivered++;
    }
    return RelayInboxDrainResult(
      processed: pending.length,
      delivered: delivered,
    );
  }
}

bool _isValidMessageId(String value) {
  return value.isNotEmpty && value.length <= 256;
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
