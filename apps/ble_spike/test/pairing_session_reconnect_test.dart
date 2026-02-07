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

  @override
  Future<SimpleKeyPair> ensureDeviceStaticKeyPairX25519() async => _staticKeyPair;

  Future<String> _contactIdFromPubkey(Uint8List staticPubkeyX25519) async {
    final digest = await Sha256().hash(staticPubkeyX25519);
    final idBytes = Uint8List.fromList(digest.bytes.sublist(0, 16));
    return base64UrlEncodeNoPad(idBytes);
  }

  Future<void> addTrustedPeer(Uint8List peerStaticPubkeyX25519, {String nickname = 'Peer'}) async {
    final id = await _contactIdFromPubkey(peerStaticPubkeyX25519);
    _contacts[id] = Contact(
      contactId: id,
      nickname: nickname,
      trusted: true,
      staticPubkey: Uint8List.fromList(peerStaticPubkeyX25519),
      currentKeyId: '',
      lastSeenAtMs: 0,
      lastRefreshAtMs: 0,
      blocked: false,
      note: null,
    );
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
    if (contact.staticPubkey == null || contact.staticPubkey!.length != 32) return null;
    return contact;
  }

  @override
  Future<Contact> upsertTrustedContactFromStaticPubkey({
    required Uint8List peerStaticPubkeyX25519,
    String? nickname,
  }) async {
    final id = await _contactIdFromPubkey(peerStaticPubkeyX25519);
    final existing = _contacts[id];
    final contact = Contact(
      contactId: id,
      nickname: nickname ?? existing?.nickname ?? 'Peer',
      trusted: true,
      staticPubkey: Uint8List.fromList(peerStaticPubkeyX25519),
      currentKeyId: existing?.currentKeyId ?? '',
      lastSeenAtMs: 0,
      lastRefreshAtMs: existing?.lastRefreshAtMs ?? 0,
      blocked: existing?.blocked ?? false,
      note: existing?.note,
    );
    _contacts[id] = contact;
    return contact;
  }
}

Future<void> _pumpHandshake({
  required PairingSession a,
  required PairingSession b,
  required List<Uint8List> aToB,
  required List<Uint8List> bToA,
  int maxRounds = 200,
}) async {
  var rounds = 0;
  while (rounds < maxRounds) {
    rounds += 1;

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

    if (a.stage == PairingStage.established && b.stage == PairingStage.established) return;
    if (a.stage == PairingStage.failed || b.stage == PairingStage.failed) return;

    await Future<void>.delayed(Duration.zero);
    if (!progressed) {
      // Allow unawaited sends to show up in the next tick.
      await Future<void>.delayed(Duration.zero);
    }
  }

  fail('handshake did not converge within $maxRounds rounds (a=${a.stage}, b=${b.stage})');
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
    await aStore.addTrustedPeer(Uint8List.fromList(bPub.bytes), nickname: 'B');
    await bStore.addTrustedPeer(Uint8List.fromList(aPub.bytes), nickname: 'A');

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
}

