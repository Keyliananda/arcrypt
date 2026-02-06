import 'package:ble_spike/security/noise_xx.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Noise XX handshake derives same hash and keys', () async {
    final dh = X25519();
    final initiatorStatic = await dh.newKeyPair();
    final responderStatic = await dh.newKeyPair();

    final initiator = NoiseXXInitiator(staticKeyPair: initiatorStatic);
    final responder = NoiseXXResponder(staticKeyPair: responderStatic);

    final m1 = await initiator.startMessage1();
    final m2 = await responder.readMessage1AndWriteMessage2(m1);
    final m3 = await initiator.readMessage2AndWriteMessage3(m2);
    await responder.readMessage3(m3);

    final iRes = await initiator.finish();
    final rRes = await responder.finish();

    expect(iRes.handshakeHash, rRes.handshakeHash);
    expect(iRes.peerStaticPublicKey, (await responderStatic.extractPublicKey()).bytes);
    expect(rRes.peerStaticPublicKey, (await initiatorStatic.extractPublicKey()).bytes);

    final iTx = await iRes.initiatorToResponderKey.extractBytes();
    final iRx = await iRes.responderToInitiatorKey.extractBytes();
    final rTx = await rRes.responderToInitiatorKey.extractBytes(); // responder tx is k2
    final rRx = await rRes.initiatorToResponderKey.extractBytes(); // responder rx is k1

    expect(iTx, rRx);
    expect(iRx, rTx);

    final sasI = sasString6FromHandshakeHash(iRes.handshakeHash);
    final sasR = sasString6FromHandshakeHash(rRes.handshakeHash);
    expect(sasI, sasR);
    expect(sasI.length, 6);
  });
}

