import 'package:ble_spike/transport/relay_config_resolver.dart';
import 'package:ble_spike/transport/relay_runtime_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const environmentConfig = RelayRuntimeConfig(
    baseUrl: 'https://relay.env.example',
    inboundMailboxId: 'env-in',
    outboundMailboxId: 'env-out',
    wakeHmacSecret: '',
    peerWakeToken: '',
  );

  test('uses runtime config when runtime config is valid', () {
    const runtimeConfig = RelayRuntimeConfig(
      baseUrl: 'https://relay.runtime.example',
      inboundMailboxId: 'runtime-in',
      outboundMailboxId: 'runtime-out',
      wakeHmacSecret: '',
      peerWakeToken: '',
    );

    final result = resolveRelayRuntimeConfig(
      environmentConfig: environmentConfig,
      runtimeConfig: runtimeConfig,
    );

    expect(result.source, RelayConfigSource.runtime);
    expect(result.config.baseUrl, 'https://relay.runtime.example');
    expect(result.runtimePresentButInvalid, isFalse);
    expect(result.healthReason, RelayConfigHealthReason.okRuntime);
  });

  test('falls back to build config when runtime config is invalid', () {
    const runtimeConfig = RelayRuntimeConfig(
      baseUrl: '',
      inboundMailboxId: 'runtime-in',
      outboundMailboxId: 'runtime-out',
      wakeHmacSecret: '',
      peerWakeToken: '',
    );

    final result = resolveRelayRuntimeConfig(
      environmentConfig: environmentConfig,
      runtimeConfig: runtimeConfig,
    );

    expect(result.source, RelayConfigSource.environment);
    expect(result.config.baseUrl, 'https://relay.env.example');
    expect(result.runtimePresentButInvalid, isTrue);
    expect(
      result.healthReason,
      RelayConfigHealthReason.runtimeInvalidFallbackEnvironment,
    );
  });

  test('uses environment config when runtime config is absent', () {
    final result = resolveRelayRuntimeConfig(
      environmentConfig: environmentConfig,
      runtimeConfig: null,
    );

    expect(result.source, RelayConfigSource.environment);
    expect(result.config.baseUrl, 'https://relay.env.example');
    expect(result.runtimePresentButInvalid, isFalse);
    expect(result.healthReason, RelayConfigHealthReason.okEnvironment);
  });

  test('returns environment invalid reason when only invalid env exists', () {
    const invalidEnvironment = RelayRuntimeConfig(
      baseUrl: 'https://relay.env.example',
      inboundMailboxId: '',
      outboundMailboxId: '',
      wakeHmacSecret: '',
      peerWakeToken: '',
    );

    final result = resolveRelayRuntimeConfig(
      environmentConfig: invalidEnvironment,
      runtimeConfig: null,
    );

    expect(result.source, RelayConfigSource.environment);
    expect(result.healthReason, RelayConfigHealthReason.environmentInvalid);
  });

  test('returns missing reason when runtime and env are empty', () {
    final result = resolveRelayRuntimeConfig(
      environmentConfig: RelayRuntimeConfig.empty,
      runtimeConfig: null,
    );

    expect(result.source, RelayConfigSource.environment);
    expect(
      result.healthReason,
      RelayConfigHealthReason.missingRuntimeAndEnvironment,
    );
  });
}
