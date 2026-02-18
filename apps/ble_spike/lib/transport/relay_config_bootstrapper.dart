import 'relay_runtime_config.dart';

enum RelayBootstrapStatus {
  bootstrappedFromEnvironment,
  skippedRuntimeAlreadyPresent,
  skippedRuntimePresentButInvalid,
  skippedEnvironmentInvalid,
  failedToPersist,
}

class RelayBootstrapOutcome {
  const RelayBootstrapOutcome({
    required this.status,
    required this.runtimeConfig,
  });

  final RelayBootstrapStatus status;
  final RelayRuntimeConfig? runtimeConfig;
}

typedef LoadRelayRuntimeConfig = Future<RelayRuntimeConfig?> Function();
typedef SaveRelayRuntimeConfig =
    Future<void> Function(RelayRuntimeConfig config);

class RelayConfigBootstrapper {
  const RelayConfigBootstrapper({
    required this.loadRuntimeConfig,
    required this.saveRuntimeConfig,
  });

  final LoadRelayRuntimeConfig loadRuntimeConfig;
  final SaveRelayRuntimeConfig saveRuntimeConfig;

  Future<RelayBootstrapOutcome> ensureRuntimeConfig({
    required RelayRuntimeConfig environmentConfig,
  }) async {
    final runtimeConfig = await loadRuntimeConfig();
    if (runtimeConfig != null && runtimeConfig.hasAnyValue) {
      if (runtimeConfig.isRemoteAvailable) {
        return RelayBootstrapOutcome(
          status: RelayBootstrapStatus.skippedRuntimeAlreadyPresent,
          runtimeConfig: runtimeConfig,
        );
      }
      return RelayBootstrapOutcome(
        status: RelayBootstrapStatus.skippedRuntimePresentButInvalid,
        runtimeConfig: runtimeConfig,
      );
    }

    if (!environmentConfig.isRemoteAvailable) {
      return const RelayBootstrapOutcome(
        status: RelayBootstrapStatus.skippedEnvironmentInvalid,
        runtimeConfig: null,
      );
    }

    try {
      await saveRuntimeConfig(environmentConfig);
      return RelayBootstrapOutcome(
        status: RelayBootstrapStatus.bootstrappedFromEnvironment,
        runtimeConfig: environmentConfig,
      );
    } catch (_) {
      return const RelayBootstrapOutcome(
        status: RelayBootstrapStatus.failedToPersist,
        runtimeConfig: null,
      );
    }
  }
}
