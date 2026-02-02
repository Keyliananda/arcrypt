import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'chat_ids.dart';
import 'chat_models.dart';

const String kAppMetaKey = 'meta';

class ChatStorage {
  ChatStorage._();

  static final ChatStorage instance = ChatStorage._();

  bool _initialized = false;

  Future<void> init({String? path}) async {
    if (_initialized) {
      return;
    }

    if (path == null) {
      await Hive.initFlutter();
    } else {
      Hive.init(path);
    }

    _registerAdapters();

    await Future.wait([
      Hive.openBox<AppMeta>(kAppMetaBox),
      Hive.openBox<Contact>(kContactsBox),
      Hive.openBox<KeyMaterial>(kKeysBox),
      Hive.openBox<Conversation>(kConversationsBox),
      Hive.openBox<ChatMessage>(kMessagesBox),
    ]);

    _initialized = true;
  }

  Box<AppMeta> get appMetaBox => Hive.box<AppMeta>(kAppMetaBox);
  Box<Contact> get contactsBox => Hive.box<Contact>(kContactsBox);
  Box<KeyMaterial> get keysBox => Hive.box<KeyMaterial>(kKeysBox);
  Box<Conversation> get conversationsBox => Hive.box<Conversation>(kConversationsBox);
  Box<ChatMessage> get messagesBox => Hive.box<ChatMessage>(kMessagesBox);

  Future<AppMeta> ensureAppMeta() async {
    final box = appMetaBox;
    final existing = box.get(kAppMetaKey);
    if (existing != null) {
      return existing;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final meta = AppMeta(
      schemaVersion: 1,
      deviceId: randomBytes(16),
      createdAtMs: now,
    );
    await box.put(kAppMetaKey, meta);
    return meta;
  }

  void _registerAdapters() {
    if (!Hive.isAdapterRegistered(kAppMetaTypeId)) {
      Hive.registerAdapter(AppMetaAdapter());
    }
    if (!Hive.isAdapterRegistered(kContactTypeId)) {
      Hive.registerAdapter(ContactAdapter());
    }
    if (!Hive.isAdapterRegistered(kKeyMaterialTypeId)) {
      Hive.registerAdapter(KeyMaterialAdapter());
    }
    if (!Hive.isAdapterRegistered(kConversationTypeId)) {
      Hive.registerAdapter(ConversationAdapter());
    }
    if (!Hive.isAdapterRegistered(kChatMessageTypeId)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
  }
}
