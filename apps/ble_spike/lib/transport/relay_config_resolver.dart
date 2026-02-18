import 'relay_runtime_config.dart';

enum RelayConfigSource { runtime, environment }

class RelayConfigResolution {
  const RelayConfigResolution({
    required this.config,
    required this.source,
    required this.runtimePresentButInvalid,
  });

  final RelayRuntimeConfig config;
  final RelayConfigSource source;
  final bool runtimePresentButInvalid;
}

RelayConfigResolution resolveRelayRuntimeConfig({
  required RelayRuntimeConfig environmentConfig,
  required RelayRuntimeConfig? runtimeConfig,
}) {
  if (runtimeConfig != null && runtimeConfig.hasAnyValue) {
    if (runtimeConfig.isRemoteAvailable) {
      return RelayConfigResolution(
        config: runtimeConfig,
        source: RelayConfigSource.runtime,
        runtimePresentButInvalid: false,
      );
    }
    if (environmentConfig.isRemoteAvailable) {
      return RelayConfigResolution(
        config: environmentConfig,
        source: RelayConfigSource.environment,
        runtimePresentButInvalid: true,
      );
    }
    return RelayConfigResolution(
      config: runtimeConfig,
      source: RelayConfigSource.runtime,
      runtimePresentButInvalid: true,
    );
  }

  return RelayConfigResolution(
    config: environmentConfig,
    source: RelayConfigSource.environment,
    runtimePresentButInvalid: false,
  );
}
