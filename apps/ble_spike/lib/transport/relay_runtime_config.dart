class RelayRuntimeConfig {
  const RelayRuntimeConfig({
    required this.baseUrl,
    required this.inboundMailboxId,
    required this.outboundMailboxId,
    required this.wakeHmacSecret,
    required this.peerWakeToken,
  });

  static const RelayRuntimeConfig empty = RelayRuntimeConfig(
    baseUrl: '',
    inboundMailboxId: '',
    outboundMailboxId: '',
    wakeHmacSecret: '',
    peerWakeToken: '',
  );

  static const RelayRuntimeConfig fromEnvironment = RelayRuntimeConfig(
    baseUrl: String.fromEnvironment('PRSM_RELAY_BASE_URL', defaultValue: ''),
    inboundMailboxId: String.fromEnvironment(
      'PRSM_RELAY_INBOUND_MAILBOX_ID',
      defaultValue: '',
    ),
    outboundMailboxId: String.fromEnvironment(
      'PRSM_RELAY_OUTBOUND_MAILBOX_ID',
      defaultValue: '',
    ),
    wakeHmacSecret: String.fromEnvironment(
      'PRSM_RELAY_WAKE_HMAC_SECRET',
      defaultValue: '',
    ),
    peerWakeToken: String.fromEnvironment(
      'PRSM_RELAY_PEER_WAKE_TOKEN',
      defaultValue: '',
    ),
  );

  final String baseUrl;
  final String inboundMailboxId;
  final String outboundMailboxId;
  final String wakeHmacSecret;
  final String peerWakeToken;

  factory RelayRuntimeConfig.fromJson(Map<String, dynamic> json) {
    return RelayRuntimeConfig(
      baseUrl: (json['baseUrl'] as String?) ?? '',
      inboundMailboxId: (json['inboundMailboxId'] as String?) ?? '',
      outboundMailboxId: (json['outboundMailboxId'] as String?) ?? '',
      wakeHmacSecret: (json['wakeHmacSecret'] as String?) ?? '',
      peerWakeToken: (json['peerWakeToken'] as String?) ?? '',
    );
  }

  Uri? get baseUri {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.host.isEmpty || parsed.scheme.isEmpty) {
      return null;
    }
    return parsed;
  }

  bool get hasMailboxIds {
    return inboundMailboxId.trim().isNotEmpty &&
        outboundMailboxId.trim().isNotEmpty;
  }

  bool get hasAnyValue {
    return baseUrl.trim().isNotEmpty ||
        inboundMailboxId.trim().isNotEmpty ||
        outboundMailboxId.trim().isNotEmpty ||
        wakeHmacSecret.trim().isNotEmpty ||
        peerWakeToken.trim().isNotEmpty;
  }

  bool get isRemoteAvailable => baseUri != null && hasMailboxIds;

  bool get isWakeConfigured => wakeHmacSecret.trim().isNotEmpty;

  String get remoteStatusLabel {
    if (isRemoteAvailable) {
      return isWakeConfigured
          ? 'Remote verfuegbar (Wake bereit)'
          : 'Remote verfuegbar';
    }
    final trimmedBaseUrl = baseUrl.trim();
    if (trimmedBaseUrl.isEmpty) {
      return 'Remote nicht konfiguriert (Relay URL fehlt)';
    }
    if (baseUri == null) {
      return 'Remote nicht konfiguriert (Relay URL ungueltig)';
    }
    return 'Remote nicht konfiguriert (Mailbox IDs fehlen)';
  }

  Map<String, String> toJson() {
    return {
      'baseUrl': baseUrl,
      'inboundMailboxId': inboundMailboxId,
      'outboundMailboxId': outboundMailboxId,
      'wakeHmacSecret': wakeHmacSecret,
      'peerWakeToken': peerWakeToken,
    };
  }
}
