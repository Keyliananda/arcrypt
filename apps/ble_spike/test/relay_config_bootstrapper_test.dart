import 'package:ble_spike/transport/relay_config_bootstrapper.dart';
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

  test('bootstraps from environment when runtime is missing', () async {
    RelayRuntimeConfig? persisted;

    final bootstrapper = RelayConfigBootstrapper(
      loadRuntimeConfig: () async => null,
      saveRuntimeConfig: (config) async {
        persisted = config;
      },
    );

    final outcome = await bootstrapper.ensureRuntimeConfig(
      environmentConfig: environmentConfig,
    );

    expect(outcome.status, RelayBootstrapStatus.bootstrappedFromEnvironment);
    expect(outcome.runtimeConfig?.baseUrl, environmentConfig.baseUrl);
    expect(persisted?.baseUrl, environmentConfig.baseUrl);
  });

  test('does not overwrite existing invalid runtime config', () async {
    const invalidRuntime = RelayRuntimeConfig(
      baseUrl: '',
      inboundMailboxId: 'runtime-in',
      outboundMailboxId: 'runtime-out',
      wakeHmacSecret: '',
      peerWakeToken: '',
    );
    var saveCalled = false;

    final bootstrapper = RelayConfigBootstrapper(
      loadRuntimeConfig: () async => invalidRuntime,
      saveRuntimeConfig: (_) async {
        saveCalled = true;
      },
    );

    final outcome = await bootstrapper.ensureRuntimeConfig(
      environmentConfig: environmentConfig,
    );

    expect(
      outcome.status,
      RelayBootstrapStatus.skippedRuntimePresentButInvalid,
    );
    expect(
      outcome.runtimeConfig?.inboundMailboxId,
      invalidRuntime.inboundMailboxId,
    );
    expect(saveCalled, isFalse);
  });

  test('skips bootstrap when environment config is invalid', () async {
    const invalidEnvironment = RelayRuntimeConfig(
      baseUrl: '',
      inboundMailboxId: 'env-in',
      outboundMailboxId: 'env-out',
      wakeHmacSecret: '',
      peerWakeToken: '',
    );
    var saveCalled = false;

    final bootstrapper = RelayConfigBootstrapper(
      loadRuntimeConfig: () async => null,
      saveRuntimeConfig: (_) async {
        saveCalled = true;
      },
    );

    final outcome = await bootstrapper.ensureRuntimeConfig(
      environmentConfig: invalidEnvironment,
    );

    expect(outcome.status, RelayBootstrapStatus.skippedEnvironmentInvalid);
    expect(outcome.runtimeConfig, isNull);
    expect(saveCalled, isFalse);
  });
}
