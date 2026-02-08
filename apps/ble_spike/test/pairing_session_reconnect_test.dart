import 'dart:typed_data';

import 'package:ble_spike/chat/chat.dart';
import 'package:ble_spike/security/pairing_session.dart';
import 'package:ble_spike/security/pairing_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePairingStorage implements PairingStorage {
  _FakePairingStorage(this._staticKeyPair);

  final SimpleKeyPair _staticKeyPair;
  final Map<String, Contact> _contacts = <String, Contact>{};
  final Map<String, KeyMaterial> _keys = <String, KeyMaterial>{};

  @override
  Future<SimpleKeyPair> ensureDeviceStaticKeyPairX25519() async =>
      _staticKeyPair;

  Future<String> _contactIdFromPubkey(Uint8List staticPubkeyX25519) async {
    final digest = await Sha256().hash(staticPubkeyX25519);
    final idBytes = Uint8List.fromList(digest.bytes.sublist(0, 16));
    return base64UrlEncodeNoPad(idBytes);
  }

  @override
  Future<Contact?> findContactById(String contactId) async {
    return _contacts[contactId];
  }

  @override
  Future<KeyMaterial?> findCurrentKeyForContact(String contactId) async {
    final contact = _contacts[contactId];
    if (contact == null || contact.currentKeyId.isEmpty) return null;
    return _keys[contact.currentKeyId];
  }

  @override
  Future<KeyMaterial?> findKeyById(String keyId) async {
    return _keys[keyId];
  }

  @override
  Future<KeyMaterial?> findPendingKeyForContact(String contactId) async {
    final contact = _contacts[contactId];
    if (contact == null || contact.pendingKeyId.isEmpty) return null;
    return _keys[contact.pendingKeyId];
  }

  @override
  Future<Contact?> findTrustedContactByStaticPubkeyX25519({
    required Uint8List peerStaticPubkeyX25519,
  }) async {
    final id = await _contactIdFromPubkey(peerStaticPubkeyX25519);
    final contact = _contacts[id];
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
    final id = await _contactIdFromPubkey(peerStaticPubkeyX25519);
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = _contacts[id];
    final contact = Contact(
      contactId: id,
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
    _contacts[id] = contact;
    return contact;
  }

  @override
  Future<KeyMaterial> preparePendingKeyForContact({
    required String contactId,
    required String keyId,
    required Uint8List masterKey32,
    required int nowMs,
  }) async {
    final contact = _contacts[contactId];
    if (contact == null) {
      throw StateError('contact missing');
    }
    final pending = KeyMaterial(
      keyId: keyId,
      contactId: contactId,
      masterKey: Uint8List.fromList(masterKey32),
      kdfVersion: 1,
      createdAtMs: nowMs,
      retiredAtMs: null,
    );
    _keys[keyId] = pending;
    _contacts[contactId] = Contact(
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
    return pending;
  }

  @override
  Future<void> commitPendingKeyForContact({
    required String contactId,
    required String keyId,
    required int nowMs,
  }) async {
    final contact = _contacts[contactId];
    if (contact == null) {
      throw StateError('contact missing');
    }
    if (contact.pendingKeyId != keyId) {
      throw StateError('pending key mismatch');
    }
    final pending = _keys[keyId];
    if (pending == null) {
      throw StateError('pending key missing');
    }
    if (contact.currentKeyId.isNotEmpty && contact.currentKeyId != keyId) {
      final current = _keys[contact.currentKeyId];
      if (current != null) {
        _keys[current.keyId] = KeyMaterial(
          keyId: current.keyId,
          contactId: current.contactId,
          masterKey: Uint8List.fromList(current.masterKey),
          kdfVersion: current.kdfVersion,
          createdAtMs: current.createdAtMs,
          retiredAtMs: nowMs,
        );
      }
    }
    _contacts[contactId] = Contact(
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
  }

  @override
  Future<void> markContactSeen({
    required String contactId,
    required int nowMs,
  }) async {
    final contact = _contacts[contactId];
    if (contact == null) return;
    _contacts[contactId] = Contact(
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
  }
}

Future<void> _pumpHandshake({
  required PairingSession a,
  required PairingSession b,
  required List<Uint8List> aToB,
  required List<Uint8List> bToA,
  int maxRounds = 200,
  bool autoConfirmSas = true,
}) async {
  var rounds = 0;
  while (rounds < maxRounds) {
    rounds += 1;

    if (autoConfirmSas) {
      if ((a.stage == PairingStage.sasReady ||
              a.stage == PairingStage.waitingPeerSas) &&
          !a.localSasConfirmed) {
        await a.confirmSas();
      }
      if ((b.stage == PairingStage.sasReady ||
              b.stage == PairingStage.waitingPeerSas) &&
          !b.localSasConfirmed) {
        await b.confirmSas();
      }
    }

    var progressed = false;
    while (aToB.isNotEmpty) {
      progressed = true;
      final msg = aToB.removeAt(0);
      await b.handleIncoming(msg);
    }
    while (bToA.isNotEmpty) {
      progressed = true;
      final msg = bToA.removeAt(0);
      await a.handleIncoming(msg);
    }

    if (a.stage == PairingStage.established &&
        b.stage == PairingStage.established)
      return;
    if (a.stage == PairingStage.failed || b.stage == PairingStage.failed)
      return;

    await Future<void>.delayed(Duration.zero);
    if (!progressed) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  fail(
    'handshake did not converge within $maxRounds rounds (a=${a.stage}, b=${b.stage})',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trusted reconnect auto-confirms SAS and establishes', () async {
    final dh = X25519();
    final aStatic = await dh.newKeyPair();
    final bStatic = await dh.newKeyPair();
    final aPub = await aStatic.extractPublicKey();
    final bPub = await bStatic.extractPublicKey();

    final aStore = _FakePairingStorage(aStatic);
    final bStore = _FakePairingStorage(bStatic);
    await aStore.upsertTrustedContactFromStaticPubkey(
      peerStaticPubkeyX25519: Uint8List.fromList(bPub.bytes),
      nowMs: 100,
    );
    await bStore.upsertTrustedContactFromStaticPubkey(
      peerStaticPubkeyX25519: Uint8List.fromList(aPub.bytes),
      nowMs: 100,
    );

    final aToB = <Uint8List>[];
    final bToA = <Uint8List>[];

    final a = PairingSession(
      role: ChatRole.initiator,
      storage: aStore,
      send: (bytes) async => aToB.add(Uint8List.fromList(bytes)),
      onUpdate: () {},
    );
    final b = PairingSession(
      role: ChatRole.responder,
      storage: bStore,
      send: (bytes) async => bToA.add(Uint8List.fromList(bytes)),
      onUpdate: () {},
    );

    await a.startIfInitiator();
    await _pumpHandshake(a: a, b: b, aToB: aToB, bToA: bToA);

    expect(a.stage, PairingStage.established);
    expect(b.stage, PairingStage.established);
    expect(a.trustedReconnect, true);
    expect(b.trustedReconnect, true);
    expect(a.localSasConfirmed, true);
    expect(b.localSasConfirmed, true);
    expect(a.masterKey32, isNotNull);
    expect(b.masterKey32, isNotNull);
    expect(a.keyId, isNotNull);
    expect(a.keyId, b.keyId);
  });

  test('pinned peer mismatch fails (no silent downgrade)', () async {
    final dh = X25519();
    final aStatic = await dh.newKeyPair();
    final bStatic = await dh.newKeyPair();

    final aStore = _FakePairingStorage(aStatic);
    final bStore = _FakePairingStorage(bStatic);

    final aToB = <Uint8List>[];
    final bToA = <Uint8List>[];

    final wrongExpected = Uint8List.fromList(List<int>.filled(32, 7));

    final a = PairingSession(
      role: ChatRole.initiator,
      storage: aStore,
      expectedPeerStaticPubkeyX25519: wrongExpected,
      requireExpectedPeer: true,
      send: (bytes) async => aToB.add(Uint8List.fromList(bytes)),
      onUpdate: () {},
    );
    final b = PairingSession(
      role: ChatRole.responder,
      storage: bStore,
      send: (bytes) async => bToA.add(Uint8List.fromList(bytes)),
      onUpdate: () {},
    );

    await a.startIfInitiator();
    await _pumpHandshake(a: a, b: b, aToB: aToB, bToA: bToA);

    expect(a.stage, PairingStage.failed);
    expect(a.error, contains('pinned'));
    expect(b.stage, isNot(PairingStage.established));
  });

  test('refresh trigger: reuse within window, rotate after window', () async {
    final dh = X25519();
    final aStatic = await dh.newKeyPair();
    final bStatic = await dh.newKeyPair();

    final aStore = _FakePairingStorage(aStatic);
    final bStore = _FakePairingStorage(bStatic);

    var nowMs = 1_000_000;
    PairingSession buildA(List<Uint8List> queue) => PairingSession(
      role: ChatRole.initiator,
      storage: aStore,
      minStableForRefresh: Duration.zero,
      nowMs: () => nowMs,
      send: (bytes) async => queue.add(Uint8List.fromList(bytes)),
      onUpdate: () {},
    );
    PairingSession buildB(List<Uint8List> queue) => PairingSession(
      role: ChatRole.responder,
      storage: bStore,
      minStableForRefresh: Duration.zero,
      nowMs: () => nowMs,
      send: (bytes) async => queue.add(Uint8List.fromList(bytes)),
      onUpdate: () {},
    );

    {
      final aToB = <Uint8List>[];
      final bToA = <Uint8List>[];
      final a = buildA(aToB);
      final b = buildB(bToA);
      await a.startIfInitiator();
      await _pumpHandshake(a: a, b: b, aToB: aToB, bToA: bToA);
      expect(a.stage, PairingStage.established);
      expect(b.stage, PairingStage.established);
      expect(a.keyId, isNotNull);
      expect(a.keyId, b.keyId);
    }

    final firstKeyId = (await aStore.findCurrentKeyForContact(
      (await aStore.findTrustedContactByStaticPubkeyX25519(
        peerStaticPubkeyX25519: Uint8List.fromList(
          (await bStatic.extractPublicKey()).bytes,
        ),
      ))!.contactId,
    ))!.keyId;

    nowMs += 5 * 60 * 1000;
    {
      final aToB = <Uint8List>[];
      final bToA = <Uint8List>[];
      final a = buildA(aToB);
      final b = buildB(bToA);
      await a.startIfInitiator();
      await _pumpHandshake(a: a, b: b, aToB: aToB, bToA: bToA);
      expect(a.stage, PairingStage.established);
      expect(b.stage, PairingStage.established);
      expect(a.keyId, firstKeyId);
      expect(b.keyId, firstKeyId);
    }

    nowMs += 11 * 60 * 1000;
    {
      final aToB = <Uint8List>[];
      final bToA = <Uint8List>[];
      final a = buildA(aToB);
      final b = buildB(bToA);
      await a.startIfInitiator();
      await _pumpHandshake(a: a, b: b, aToB: aToB, bToA: bToA);
      expect(a.stage, PairingStage.established);
      expect(b.stage, PairingStage.established);
      expect(a.keyId, isNotNull);
      expect(a.keyId, b.keyId);
      expect(a.keyId, isNot(firstKeyId));
    }
  });

  test('rotation requires commit before responder is established', () async {
    final dh = X25519();
    final aStatic = await dh.newKeyPair();
    final bStatic = await dh.newKeyPair();

    final aStore = _FakePairingStorage(aStatic);
    final bStore = _FakePairingStorage(bStatic);

    Uint8List? heldCommit;
    final aToB = <Uint8List>[];
    final bToA = <Uint8List>[];

    final a = PairingSession(
      role: ChatRole.initiator,
      storage: aStore,
      minStableForRefresh: Duration.zero,
      send: (bytes) async {
        final msg = Uint8List.fromList(bytes);
        if (msg.length >= 2 &&
            msg[0] == kSecMagic &&
            msg[1] == kSecMsgMasterKeyCommit) {
          heldCommit = msg;
          return;
        }
        aToB.add(msg);
      },
      onUpdate: () {},
    );
    final b = PairingSession(
      role: ChatRole.responder,
      storage: bStore,
      minStableForRefresh: Duration.zero,
      send: (bytes) async => bToA.add(Uint8List.fromList(bytes)),
      onUpdate: () {},
    );

    await a.startIfInitiator();
    var reachedPreCommitState = false;
    for (var i = 0; i < 200; i++) {
      if ((a.stage == PairingStage.sasReady ||
              a.stage == PairingStage.waitingPeerSas) &&
          !a.localSasConfirmed) {
        await a.confirmSas();
      }
      if ((b.stage == PairingStage.sasReady ||
              b.stage == PairingStage.waitingPeerSas) &&
          !b.localSasConfirmed) {
        await b.confirmSas();
      }

      var progressed = false;
      while (aToB.isNotEmpty) {
        progressed = true;
        final msg = aToB.removeAt(0);
        await b.handleIncoming(msg);
      }
      while (bToA.isNotEmpty) {
        progressed = true;
        final msg = bToA.removeAt(0);
        await a.handleIncoming(msg);
      }

      if (a.stage == PairingStage.established &&
          b.stage == PairingStage.waitingMasterKeyCommit &&
          heldCommit != null) {
        reachedPreCommitState = true;
        break;
      }
      if (a.stage == PairingStage.failed || b.stage == PairingStage.failed) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
      if (!progressed) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    expect(reachedPreCommitState, isTrue);
    expect(a.stage, PairingStage.established);
    expect(b.stage, PairingStage.waitingMasterKeyCommit);
    expect(heldCommit, isNotNull);

    aToB.add(heldCommit!);
    await _pumpHandshake(
      a: a,
      b: b,
      aToB: aToB,
      bToA: bToA,
      autoConfirmSas: true,
    );
    expect(b.stage, PairingStage.established);
  });
}
