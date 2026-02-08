import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cryptography/cryptography.dart';

import 'chat_ids.dart';
import 'chat_models.dart';
import '../security/pairing_storage.dart';

const String kAppMetaKey = 'meta';
const String kSecurityBox = 'security';
const String kDeviceStaticPrivX25519Key = 'device_static_priv_x25519';
const String kDeviceStaticPubX25519Key = 'device_static_pub_x25519';

class ChatStorage implements PairingStorage {
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
      Hive.openBox<SessionCounterState>(kSessionStateBox),
      Hive.openBox<Uint8List>(kSecurityBox),
    ]);

    _initialized = true;
  }

  Box<AppMeta> get appMetaBox => Hive.box<AppMeta>(kAppMetaBox);
  Box<Contact> get contactsBox => Hive.box<Contact>(kContactsBox);
  Box<KeyMaterial> get keysBox => Hive.box<KeyMaterial>(kKeysBox);
  Box<Conversation> get conversationsBox =>
      Hive.box<Conversation>(kConversationsBox);
  Box<ChatMessage> get messagesBox => Hive.box<ChatMessage>(kMessagesBox);
  Box<SessionCounterState> get sessionStateBox =>
      Hive.box<SessionCounterState>(kSessionStateBox);
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
    if (!Hive.isAdapterRegistered(kSessionCounterStateTypeId)) {
      Hive.registerAdapter(SessionCounterStateAdapter());
    }
  }

  @override
  Future<SimpleKeyPair> ensureDeviceStaticKeyPairX25519() async {
    final box = securityBox;
    final priv = box.get(kDeviceStaticPrivX25519Key);
    final pub = box.get(kDeviceStaticPubX25519Key);
    if (priv != null && pub != null && priv.length == 32 && pub.length == 32) {
      return SimpleKeyPairData(
        Uint8List.fromList(priv),
        publicKey: SimplePublicKey(
          Uint8List.fromList(pub),
          type: KeyPairType.x25519,
        ),
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

  Future<String> contactIdFromStaticPubkeyX25519(
    Uint8List peerStaticPubkeyX25519,
  ) async {
    if (peerStaticPubkeyX25519.length != 32) {
      throw ArgumentError('peerStaticPubkeyX25519 must be 32 bytes');
    }
    final digest = await Sha256().hash(peerStaticPubkeyX25519);
    final idBytes = Uint8List.fromList(digest.bytes.sublist(0, 16));
    return base64UrlEncodeNoPad(idBytes);
  }

  @override
  Future<Contact?> findTrustedContactByStaticPubkeyX25519({
    required Uint8List peerStaticPubkeyX25519,
  }) async {
    final contactId = await contactIdFromStaticPubkeyX25519(
      peerStaticPubkeyX25519,
    );
    final contact = contactsBox.get(contactId);
    if (contact == null) return null;
    if (!contact.trusted) return null;
    if (contact.blocked) return null;
    if (contact.staticPubkey == null || contact.staticPubkey!.length != 32)
      return null;
    return contact;
  }

  @override
  Future<Contact> upsertTrustedContactFromStaticPubkey({
    required Uint8List peerStaticPubkeyX25519,
    String? nickname,
    int? nowMs,
  }) async {
    if (peerStaticPubkeyX25519.length != 32) {
      throw ArgumentError('peerStaticPubkeyX25519 must be 32 bytes');
    }

    final contactId = await contactIdFromStaticPubkeyX25519(
      peerStaticPubkeyX25519,
    );

    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
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
      pendingKeyId: existing?.pendingKeyId ?? '',
      note: existing?.note,
    );
    await box.put(contactId, contact);
    return contact;
  }

  @override
  Future<Contact?> findContactById(String contactId) async {
    return contactsBox.get(contactId);
  }

  @override
  Future<KeyMaterial?> findKeyById(String keyId) async {
    return keysBox.get(keyId);
  }

  @override
  Future<KeyMaterial?> findCurrentKeyForContact(String contactId) async {
    final contact = contactsBox.get(contactId);
    if (contact == null || contact.currentKeyId.isEmpty) return null;
    return keysBox.get(contact.currentKeyId);
  }

  @override
  Future<KeyMaterial?> findPendingKeyForContact(String contactId) async {
    final contact = contactsBox.get(contactId);
    if (contact == null || contact.pendingKeyId.isEmpty) return null;
    return keysBox.get(contact.pendingKeyId);
  }

  @override
  Future<KeyMaterial> preparePendingKeyForContact({
    required String contactId,
    required String keyId,
    required Uint8List masterKey32,
    required int nowMs,
  }) async {
    if (masterKey32.length != 32) {
      throw ArgumentError('masterKey32 must be 32 bytes');
    }
    final contact = contactsBox.get(contactId);
    if (contact == null) {
      throw StateError('contact not found: $contactId');
    }

    if (contact.pendingKeyId.isNotEmpty && contact.pendingKeyId != keyId) {
      await keysBox.delete(contact.pendingKeyId);
    }

    final pending = KeyMaterial(
      keyId: keyId,
      contactId: contactId,
      masterKey: Uint8List.fromList(masterKey32),
      kdfVersion: 1,
      createdAtMs: nowMs,
      retiredAtMs: null,
    );
    await keysBox.put(keyId, pending);

    final updated = Contact(
      contactId: contact.contactId,
      nickname: contact.nickname,
      trusted: contact.trusted,
      staticPubkey: contact.staticPubkey == null
          ? null
          : Uint8List.fromList(contact.staticPubkey!),
      currentKeyId: contact.currentKeyId,
      lastSeenAtMs: nowMs,
      lastRefreshAtMs: contact.lastRefreshAtMs,
      blocked: contact.blocked,
      pendingKeyId: keyId,
      note: contact.note,
    );
    await contactsBox.put(contactId, updated);
    return pending;
  }

  @override
  Future<void> commitPendingKeyForContact({
    required String contactId,
    required String keyId,
    required int nowMs,
  }) async {
    final contact = contactsBox.get(contactId);
    if (contact == null) {
      throw StateError('contact not found: $contactId');
    }
    if (contact.pendingKeyId != keyId) {
      throw StateError('pending key mismatch for contact $contactId');
    }

    final pending = keysBox.get(keyId);
    if (pending == null) {
      throw StateError('pending key not found: $keyId');
    }
    if (pending.contactId != contactId) {
      throw StateError('pending key contact mismatch');
    }

    final previousKeyId = contact.currentKeyId;
    if (previousKeyId.isNotEmpty && previousKeyId != keyId) {
      final previous = keysBox.get(previousKeyId);
      if (previous != null) {
        await keysBox.put(
          previousKeyId,
          KeyMaterial(
            keyId: previous.keyId,
            contactId: previous.contactId,
            masterKey: Uint8List.fromList(previous.masterKey),
            kdfVersion: previous.kdfVersion,
            createdAtMs: previous.createdAtMs,
            retiredAtMs: nowMs,
          ),
        );
      }
    }

    final updatedContact = Contact(
      contactId: contact.contactId,
      nickname: contact.nickname,
      trusted: contact.trusted,
      staticPubkey: contact.staticPubkey == null
          ? null
          : Uint8List.fromList(contact.staticPubkey!),
      currentKeyId: keyId,
      lastSeenAtMs: nowMs,
      lastRefreshAtMs: nowMs,
      blocked: contact.blocked,
      pendingKeyId: '',
      note: contact.note,
    );
    await contactsBox.put(contactId, updatedContact);
  }

  @override
  Future<void> markContactSeen({
    required String contactId,
    required int nowMs,
  }) async {
    final contact = contactsBox.get(contactId);
    if (contact == null) return;
    final updated = Contact(
      contactId: contact.contactId,
      nickname: contact.nickname,
      trusted: contact.trusted,
      staticPubkey: contact.staticPubkey == null
          ? null
          : Uint8List.fromList(contact.staticPubkey!),
      currentKeyId: contact.currentKeyId,
      lastSeenAtMs: nowMs,
      lastRefreshAtMs: contact.lastRefreshAtMs,
      blocked: contact.blocked,
      pendingKeyId: contact.pendingKeyId,
      note: contact.note,
    );
    await contactsBox.put(contactId, updated);
  }

  String _sessionStateId({
    required String contactId,
    required String keyId,
    required int sessionId,
  }) {
    return '$contactId|$keyId|${sessionId.toUnsigned(32)}';
  }

  Future<SessionCounterState> ensureSessionCounterState({
    required String contactId,
    required String keyId,
    required int sessionId,
  }) async {
    final id = _sessionStateId(
      contactId: contactId,
      keyId: keyId,
      sessionId: sessionId,
    );
    final existing = sessionStateBox.get(id);
    if (existing != null) return existing;
    final now = DateTime.now().millisecondsSinceEpoch;
    final created = SessionCounterState(
      stateId: id,
      contactId: contactId,
      keyId: keyId,
      sessionId: sessionId,
      nextTxCounter: 0,
      lastRxCounter: -1,
      updatedAtMs: now,
    );
    await sessionStateBox.put(id, created);
    return created;
  }

  Future<int> reserveNextTxCounter({
    required String contactId,
    required String keyId,
    required int sessionId,
  }) async {
    final state = await ensureSessionCounterState(
      contactId: contactId,
      keyId: keyId,
      sessionId: sessionId,
    );
    final reserved = state.nextTxCounter;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = SessionCounterState(
      stateId: state.stateId,
      contactId: state.contactId,
      keyId: state.keyId,
      sessionId: state.sessionId,
      nextTxCounter: reserved + 1,
      lastRxCounter: state.lastRxCounter,
      updatedAtMs: now,
    );
    await sessionStateBox.put(state.stateId, updated);
    return reserved;
  }

  Future<void> commitLastRxCounter({
    required String contactId,
    required String keyId,
    required int sessionId,
    required int counter,
  }) async {
    final state = await ensureSessionCounterState(
      contactId: contactId,
      keyId: keyId,
      sessionId: sessionId,
    );
    if (counter <= state.lastRxCounter) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = SessionCounterState(
      stateId: state.stateId,
      contactId: state.contactId,
      keyId: state.keyId,
      sessionId: state.sessionId,
      nextTxCounter: state.nextTxCounter,
      lastRxCounter: counter,
      updatedAtMs: now,
    );
    await sessionStateBox.put(state.stateId, updated);
  }
}
