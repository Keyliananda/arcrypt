import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cryptography/cryptography.dart';

import 'chat_ids.dart';
import 'chat_models.dart';

const String kAppMetaKey = 'meta';
const String kSecurityBox = 'security';
const String kDeviceStaticPrivX25519Key = 'device_static_priv_x25519';
const String kDeviceStaticPubX25519Key = 'device_static_pub_x25519';

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
      Hive.openBox<Uint8List>(kSecurityBox),
    ]);

    _initialized = true;
  }

  Box<AppMeta> get appMetaBox => Hive.box<AppMeta>(kAppMetaBox);
  Box<Contact> get contactsBox => Hive.box<Contact>(kContactsBox);
  Box<KeyMaterial> get keysBox => Hive.box<KeyMaterial>(kKeysBox);
  Box<Conversation> get conversationsBox => Hive.box<Conversation>(kConversationsBox);
  Box<ChatMessage> get messagesBox => Hive.box<ChatMessage>(kMessagesBox);
  Box<Uint8List> get securityBox => Hive.box<Uint8List>(kSecurityBox);

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

  Future<SimpleKeyPair> ensureDeviceStaticKeyPairX25519() async {
    final box = securityBox;
    final priv = box.get(kDeviceStaticPrivX25519Key);
    final pub = box.get(kDeviceStaticPubX25519Key);
    if (priv != null && pub != null && priv.length == 32 && pub.length == 32) {
      return SimpleKeyPairData(
        Uint8List.fromList(priv),
        publicKey: SimplePublicKey(Uint8List.fromList(pub), type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );
    }

    final x25519 = X25519();
    final keyPair = await x25519.newKeyPair();
    final extracted = await keyPair.extract();
    final privBytes = Uint8List.fromList(extracted.bytes);
    final pubBytes = Uint8List.fromList(extracted.publicKey.bytes);
    await box.put(kDeviceStaticPrivX25519Key, privBytes);
    await box.put(kDeviceStaticPubX25519Key, pubBytes);
    return SimpleKeyPairData(
      privBytes,
      publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  Future<Contact> upsertTrustedContactFromStaticPubkey({
    required Uint8List peerStaticPubkeyX25519,
    String? nickname,
  }) async {
    if (peerStaticPubkeyX25519.length != 32) {
      throw ArgumentError('peerStaticPubkeyX25519 must be 32 bytes');
    }

    final digest = await Sha256().hash(peerStaticPubkeyX25519);
    final idBytes = Uint8List.fromList(digest.bytes.sublist(0, 16));
    final contactId = base64UrlEncodeNoPad(idBytes);

    final now = DateTime.now().millisecondsSinceEpoch;
    final box = contactsBox;
    final existing = box.get(contactId);
    final contact = Contact(
      contactId: contactId,
      nickname: nickname ?? existing?.nickname ?? 'Peer',
      trusted: true,
      staticPubkey: Uint8List.fromList(peerStaticPubkeyX25519),
      currentKeyId: existing?.currentKeyId ?? '',
      lastSeenAtMs: now,
      lastRefreshAtMs: existing?.lastRefreshAtMs ?? 0,
      blocked: existing?.blocked ?? false,
      note: existing?.note,
    );
    await box.put(contactId, contact);
    return contact;
  }
}
