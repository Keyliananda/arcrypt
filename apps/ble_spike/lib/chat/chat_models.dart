import 'dart:typed_data';

import 'package:hive/hive.dart';

const String kAppMetaBox = 'app_meta';
const String kContactsBox = 'contacts';
const String kKeysBox = 'keys';
const String kConversationsBox = 'conversations';
const String kMessagesBox = 'messages';
const String kSessionStateBox = 'session_state';

const int kAppMetaTypeId = 20;
const int kContactTypeId = 21;
const int kKeyMaterialTypeId = 22;
const int kConversationTypeId = 23;
const int kChatMessageTypeId = 24;
const int kSessionCounterStateTypeId = 25;

class MessageDirection {
  const MessageDirection._();

  static const int inbound = 0;
  static const int outbound = 1;
}

class MessageStatus {
  const MessageStatus._();

  static const int received = 0;
  static const int pending = 1;
  static const int sent = 2;
  static const int failed = 3;
}

class AppMeta {
  AppMeta({
    required this.schemaVersion,
    required this.deviceId,
    required this.createdAtMs,
  });

  final int schemaVersion;
  final Uint8List deviceId;
  final int createdAtMs;
}

class Contact {
  Contact({
    required this.contactId,
    required this.nickname,
    required this.trusted,
    required this.currentKeyId,
    required this.lastSeenAtMs,
    required this.lastRefreshAtMs,
    required this.blocked,
    this.pendingKeyId = '',
    this.staticPubkey,
    this.note,
  });

  final String contactId;
  final String nickname;
  final bool trusted;
  final Uint8List? staticPubkey;
  final String currentKeyId;
  final int lastSeenAtMs;
  final int lastRefreshAtMs;
  final bool blocked;
  final String pendingKeyId;
  final String? note;
}

class KeyMaterial {
  KeyMaterial({
    required this.keyId,
    required this.contactId,
    required this.masterKey,
    required this.kdfVersion,
    required this.createdAtMs,
    this.retiredAtMs,
  });

  final String keyId;
  final String contactId;
  final Uint8List masterKey;
  final int kdfVersion;
  final int createdAtMs;
  final int? retiredAtMs;
}

class Conversation {
  Conversation({
    required this.conversationId,
    required this.contactId,
    required this.unreadCount,
    required this.pinned,
    required this.archived,
    required this.muted,
    this.lastMessageId,
    this.lastMessageAtMs,
  });

  final String conversationId;
  final String contactId;
  final String? lastMessageId;
  final int? lastMessageAtMs;
  final int unreadCount;
  final bool pinned;
  final bool archived;
  final bool muted;
}

class ChatMessage {
  ChatMessage({
    required this.messageId,
    required this.conversationId,
    required this.direction,
    required this.status,
    required this.sentAtMs,
    required this.receivedAtMs,
    required this.bodyUtf8,
    required this.keyId,
    required this.counter,
    required this.sessionId,
  });

  final String messageId;
  final String conversationId;
  final int direction;
  final int status;
  final int sentAtMs;
  final int receivedAtMs;
  final String bodyUtf8;
  final String keyId;
  final int counter;
  final int sessionId;
}

class SessionCounterState {
  SessionCounterState({
    required this.stateId,
    required this.contactId,
    required this.keyId,
    required this.sessionId,
    required this.nextTxCounter,
    required this.lastRxCounter,
    required this.rxSeenWindowBits,
    required this.updatedAtMs,
  });

  final String stateId;
  final String contactId;
  final String keyId;
  final int sessionId;
  final int nextTxCounter;
  final int lastRxCounter;
  final int rxSeenWindowBits;
  final int updatedAtMs;
}

class AppMetaAdapter extends TypeAdapter<AppMeta> {
  @override
  final int typeId = kAppMetaTypeId;

  @override
  AppMeta read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return AppMeta(
      schemaVersion: fields[0] as int? ?? 1,
      deviceId: (fields[1] as Uint8List?) ?? Uint8List(0),
      createdAtMs: fields[2] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, AppMeta obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.schemaVersion)
      ..writeByte(1)
      ..write(obj.deviceId)
      ..writeByte(2)
      ..write(obj.createdAtMs);
  }
}

class ContactAdapter extends TypeAdapter<Contact> {
  @override
  final int typeId = kContactTypeId;

  @override
  Contact read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Contact(
      contactId: fields[0] as String? ?? '',
      nickname: fields[1] as String? ?? '',
      trusted: fields[2] as bool? ?? false,
      staticPubkey: fields[3] as Uint8List?,
      currentKeyId: fields[4] as String? ?? '',
      lastSeenAtMs: fields[5] as int? ?? 0,
      lastRefreshAtMs: fields[6] as int? ?? 0,
      blocked: fields[7] as bool? ?? false,
      note: fields[8] as String?,
      pendingKeyId: fields[9] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, Contact obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.contactId)
      ..writeByte(1)
      ..write(obj.nickname)
      ..writeByte(2)
      ..write(obj.trusted)
      ..writeByte(3)
      ..write(obj.staticPubkey)
      ..writeByte(4)
      ..write(obj.currentKeyId)
      ..writeByte(5)
      ..write(obj.lastSeenAtMs)
      ..writeByte(6)
      ..write(obj.lastRefreshAtMs)
      ..writeByte(7)
      ..write(obj.blocked)
      ..writeByte(8)
      ..write(obj.note)
      ..writeByte(9)
      ..write(obj.pendingKeyId);
  }
}

class KeyMaterialAdapter extends TypeAdapter<KeyMaterial> {
  @override
  final int typeId = kKeyMaterialTypeId;

  @override
  KeyMaterial read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return KeyMaterial(
      keyId: fields[0] as String? ?? '',
      contactId: fields[1] as String? ?? '',
      masterKey: (fields[2] as Uint8List?) ?? Uint8List(0),
      kdfVersion: fields[3] as int? ?? 1,
      createdAtMs: fields[4] as int? ?? 0,
      retiredAtMs: fields[5] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, KeyMaterial obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.keyId)
      ..writeByte(1)
      ..write(obj.contactId)
      ..writeByte(2)
      ..write(obj.masterKey)
      ..writeByte(3)
      ..write(obj.kdfVersion)
      ..writeByte(4)
      ..write(obj.createdAtMs)
      ..writeByte(5)
      ..write(obj.retiredAtMs);
  }
}

class ConversationAdapter extends TypeAdapter<Conversation> {
  @override
  final int typeId = kConversationTypeId;

  @override
  Conversation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Conversation(
      conversationId: fields[0] as String? ?? '',
      contactId: fields[1] as String? ?? '',
      lastMessageId: fields[2] as String?,
      lastMessageAtMs: fields[3] as int?,
      unreadCount: fields[4] as int? ?? 0,
      pinned: fields[5] as bool? ?? false,
      archived: fields[6] as bool? ?? false,
      muted: fields[7] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Conversation obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.conversationId)
      ..writeByte(1)
      ..write(obj.contactId)
      ..writeByte(2)
      ..write(obj.lastMessageId)
      ..writeByte(3)
      ..write(obj.lastMessageAtMs)
      ..writeByte(4)
      ..write(obj.unreadCount)
      ..writeByte(5)
      ..write(obj.pinned)
      ..writeByte(6)
      ..write(obj.archived)
      ..writeByte(7)
      ..write(obj.muted);
  }
}

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = kChatMessageTypeId;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return ChatMessage(
      messageId: fields[0] as String? ?? '',
      conversationId: fields[1] as String? ?? '',
      direction: fields[2] as int? ?? MessageDirection.inbound,
      status: fields[3] as int? ?? MessageStatus.received,
      sentAtMs: fields[4] as int? ?? 0,
      receivedAtMs: fields[5] as int? ?? 0,
      bodyUtf8: fields[6] as String? ?? '',
      keyId: fields[7] as String? ?? '',
      counter: fields[8] as int? ?? 0,
      sessionId: fields[9] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.messageId)
      ..writeByte(1)
      ..write(obj.conversationId)
      ..writeByte(2)
      ..write(obj.direction)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.sentAtMs)
      ..writeByte(5)
      ..write(obj.receivedAtMs)
      ..writeByte(6)
      ..write(obj.bodyUtf8)
      ..writeByte(7)
      ..write(obj.keyId)
      ..writeByte(8)
      ..write(obj.counter)
      ..writeByte(9)
      ..write(obj.sessionId);
  }
}

class SessionCounterStateAdapter extends TypeAdapter<SessionCounterState> {
  @override
  final int typeId = kSessionCounterStateTypeId;

  @override
  SessionCounterState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return SessionCounterState(
      stateId: fields[0] as String? ?? '',
      contactId: fields[1] as String? ?? '',
      keyId: fields[2] as String? ?? '',
      sessionId: fields[3] as int? ?? 0,
      nextTxCounter: fields[4] as int? ?? 0,
      lastRxCounter: fields[5] as int? ?? -1,
      updatedAtMs: fields[6] as int? ?? 0,
      rxSeenWindowBits: fields[7] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, SessionCounterState obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.stateId)
      ..writeByte(1)
      ..write(obj.contactId)
      ..writeByte(2)
      ..write(obj.keyId)
      ..writeByte(3)
      ..write(obj.sessionId)
      ..writeByte(4)
      ..write(obj.nextTxCounter)
      ..writeByte(5)
      ..write(obj.lastRxCounter)
      ..writeByte(6)
      ..write(obj.updatedAtMs)
      ..writeByte(7)
      ..write(obj.rxSeenWindowBits);
  }
}
