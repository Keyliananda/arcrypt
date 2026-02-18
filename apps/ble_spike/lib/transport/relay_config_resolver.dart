import 'relay_runtime_config.dart';

enum RelayConfigSource { runtime, environment }

enum RelayConfigHealthReason {
  okRuntime,
  okEnvironment,
  runtimeInvalidFallbackEnvironment,
  runtimeInvalidNoFallback,
  environmentInvalid,
  missingRuntimeAndEnvironment,
}

extension RelayConfigHealthReasonX on RelayConfigHealthReason {
  String get code {
    return switch (this) {
      RelayConfigHealthReason.okRuntime => 'ok_runtime',
      RelayConfigHealthReason.okEnvironment => 'ok_environment',
      RelayConfigHealthReason.runtimeInvalidFallbackEnvironment =>
        'runtime_invalid_fallback_environment',
      RelayConfigHealthReason.runtimeInvalidNoFallback =>
        'runtime_invalid_no_fallback',
      RelayConfigHealthReason.environmentInvalid => 'environment_invalid',
      RelayConfigHealthReason.missingRuntimeAndEnvironment =>
        'missing_runtime_and_environment',
    };
  }

  String get label {
    return switch (this) {
      RelayConfigHealthReason.okRuntime => 'Runtime-Konfig aktiv',
      RelayConfigHealthReason.okEnvironment => 'Build-Konfig aktiv',
      RelayConfigHealthReason.runtimeInvalidFallbackEnvironment =>
        'Runtime ungueltig, Build-Fallback aktiv',
      RelayConfigHealthReason.runtimeInvalidNoFallback =>
        'Runtime ungueltig, kein gueltiger Fallback',
      RelayConfigHealthReason.environmentInvalid => 'Build-Konfig ungueltig',
      RelayConfigHealthReason.missingRuntimeAndEnvironment =>
        'Keine Runtime- oder Build-Konfig vorhanden',
    };
  }

  bool get isIssue {
    return switch (this) {
      RelayConfigHealthReason.okRuntime => false,
      RelayConfigHealthReason.okEnvironment => false,
      RelayConfigHealthReason.runtimeInvalidFallbackEnvironment => true,
      RelayConfigHealthReason.runtimeInvalidNoFallback => true,
      RelayConfigHealthReason.environmentInvalid => true,
      RelayConfigHealthReason.missingRuntimeAndEnvironment => true,
    };
  }
}

class RelayConfigResolution {
  const RelayConfigResolution({
    required this.config,
    required this.source,
    required this.healthReason,
  });

  final RelayRuntimeConfig config;
  final RelayConfigSource source;
  final RelayConfigHealthReason healthReason;

  bool get runtimePresentButInvalid {
    return healthReason ==
            RelayConfigHealthReason.runtimeInvalidFallbackEnvironment ||
        healthReason == RelayConfigHealthReason.runtimeInvalidNoFallback;
  }
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
        healthReason: RelayConfigHealthReason.okRuntime,
      );
    }
    if (environmentConfig.isRemoteAvailable) {
      return RelayConfigResolution(
        config: environmentConfig,
        source: RelayConfigSource.environment,
        healthReason: RelayConfigHealthReason.runtimeInvalidFallbackEnvironment,
      );
    }
    return RelayConfigResolution(
      config: runtimeConfig,
      source: RelayConfigSource.runtime,
      healthReason: RelayConfigHealthReason.runtimeInvalidNoFallback,
    );
  }

  if (environmentConfig.isRemoteAvailable) {
    return RelayConfigResolution(
      config: environmentConfig,
      source: RelayConfigSource.environment,
      healthReason: RelayConfigHealthReason.okEnvironment,
    );
  }

  if (environmentConfig.hasAnyValue) {
    return RelayConfigResolution(
      config: environmentConfig,
      source: RelayConfigSource.environment,
      healthReason: RelayConfigHealthReason.environmentInvalid,
    );
  }

  return RelayConfigResolution(
    config: environmentConfig,
    source: RelayConfigSource.environment,
    healthReason: RelayConfigHealthReason.missingRuntimeAndEnvironment,
  );
}
