import 'package:ble_spike/transport/relay_runtime_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote config unavailable when base URL is missing', () {
    const config = RelayRuntimeConfig(
      baseUrl: '',
      inboundMailboxId: 'inbound',
      outboundMailboxId: 'outbound',
      wakeHmacSecret: '',
      peerWakeToken: '',
    );

    expect(config.isRemoteAvailable, isFalse);
    expect(
      config.remoteStatusLabel,
      'Remote nicht konfiguriert (Relay URL fehlt)',
    );
  });

  test('remote config unavailable when base URL is invalid', () {
    const config = RelayRuntimeConfig(
      baseUrl: '::not-a-uri::',
      inboundMailboxId: 'inbound',
      outboundMailboxId: 'outbound',
      wakeHmacSecret: '',
      peerWakeToken: '',
    );

    expect(config.baseUri, isNull);
    expect(config.isRemoteAvailable, isFalse);
    expect(
      config.remoteStatusLabel,
      'Remote nicht konfiguriert (Relay URL ungueltig)',
    );
  });

  test('remote config unavailable when mailbox IDs are missing', () {
    const config = RelayRuntimeConfig(
      baseUrl: 'https://relay.example',
      inboundMailboxId: '',
      outboundMailboxId: '',
      wakeHmacSecret: '',
      peerWakeToken: '',
    );

    expect(config.baseUri, isNotNull);
    expect(config.isRemoteAvailable, isFalse);
    expect(
      config.remoteStatusLabel,
      'Remote nicht konfiguriert (Mailbox IDs fehlen)',
    );
  });

  test(
    'remote config available and wake-ready when all required values exist',
    () {
      const config = RelayRuntimeConfig(
        baseUrl: 'https://relay.example',
        inboundMailboxId: 'inbound',
        outboundMailboxId: 'outbound',
        wakeHmacSecret: 'wake-secret',
        peerWakeToken: 'peer-token',
      );

      expect(config.baseUri, isNotNull);
      expect(config.isRemoteAvailable, isTrue);
      expect(config.isWakeConfigured, isTrue);
      expect(config.remoteStatusLabel, 'Remote verfuegbar (Wake bereit)');
    },
  );

  test('json serialization roundtrip preserves values', () {
    const config = RelayRuntimeConfig(
      baseUrl: 'https://relay.example',
      inboundMailboxId: 'inbound',
      outboundMailboxId: 'outbound',
      wakeHmacSecret: 'wake-secret',
      peerWakeToken: 'peer-token',
    );

    final roundtrip = RelayRuntimeConfig.fromJson(config.toJson());
    expect(roundtrip.baseUrl, config.baseUrl);
    expect(roundtrip.inboundMailboxId, config.inboundMailboxId);
    expect(roundtrip.outboundMailboxId, config.outboundMailboxId);
    expect(roundtrip.wakeHmacSecret, config.wakeHmacSecret);
    expect(roundtrip.peerWakeToken, config.peerWakeToken);
  });
}
