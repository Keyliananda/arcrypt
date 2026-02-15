import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble/ble.dart';
import 'chat/chat.dart';
import 'transport/relay_inbox.dart';
import 'transport/relay_link.dart';
import 'transport/relay_outbox.dart';
import 'transport/relay_runtime_config.dart';
import 'transport/transport.dart';
import 'security/pairing_session.dart';

const String kAppVersion = '0.701';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChatStorage.instance.init();
  await ChatStorage.instance.ensureAppMeta();
  runApp(const PrsmChatApp());
}

class PrsmChatApp extends StatelessWidget {
  const PrsmChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PRSM Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const RoleSelectionScreen(),
    );
  }
}

/// Initial screen to select role: Peripheral (GATT Server) or Central (GATT Client)
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String _status = '';
  bool _checking = false;

  // Keep a single instance of CentralManager
  CentralManager? _centralManager;
  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;

  @override
  void initState() {
    super.initState();
    _initCentralManager();
    if (_centralManager == null) {
      return;
    }
    _setupBleStateListener();
    _checkPermissions();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  void _setupBleStateListener() {
    final cm = _centralManager!;
    // Listen for BLE state changes (important for iOS!)
    _stateSub = cm.stateChanged.listen((event) {
      _updateBleState(event.state);
    });
  }

  void _initCentralManager() {
    try {
      _centralManager = CentralManager();
    } on UnimplementedError {
      _centralManager = null;
      _status = 'BLE nicht verfügbar (Test/Unsupported Platform)';
      _checking = false;
    }
  }

  void _updateBleState(BluetoothLowEnergyState state) {
    if (!mounted) return;

    if (state == BluetoothLowEnergyState.poweredOn) {
      setState(() {
        _checking = false;
        _status = 'Bereit';
      });
    } else if (state == BluetoothLowEnergyState.unauthorized) {
      setState(() {
        _checking = false;
        _status =
            'Bluetooth-Berechtigung fehlt.\nBitte in den Einstellungen erlauben.';
      });
    } else if (state == BluetoothLowEnergyState.poweredOff) {
      setState(() {
        _checking = false;
        _status = 'Bluetooth ist aus. Bitte einschalten.';
      });
    } else {
      setState(() {
        _checking = false;
        _status = 'Bluetooth-Status: $state';
      });
    }
  }

  Future<void> _checkPermissions() async {
    setState(() {
      _checking = true;
      _status = 'Prüfe Berechtigungen...';
    });

    // Request permissions (Android needs explicit requests, iOS triggers on first BLE access)
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();

    final allGranted = permissions.values.every(
      (status) => status.isGranted || status.isLimited,
    );

    if (!allGranted) {
      setState(() {
        _checking = false;
        _status =
            'Bluetooth-Berechtigungen fehlen.\nBitte in den Einstellungen erlauben.';
      });
      return;
    }

    // Check current BLE state
    // On iOS, accessing .state may trigger the permission dialog
    final currentState = _centralManager!.state;
    _updateBleState(currentState);

    // If state is unknown, wait a moment for iOS to update
    if (currentState == BluetoothLowEnergyState.unknown) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _updateBleState(_centralManager!.state);
      }
    }
  }

  void _selectRole(ChatRole role) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ChatScreen(role: role)));
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _status == 'Bereit';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bluetooth, size: 80, color: Colors.teal),
              const SizedBox(height: 24),
              const Text(
                'PRSM Chat',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ende-zu-Ende verschlüsselter BLE-Chat',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                'Version $kAppVersion',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // Status
              if (_checking)
                const CircularProgressIndicator()
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isReady
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isReady ? Icons.check_circle : Icons.warning,
                        color: isReady ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(_status)),
                    ],
                  ),
                ),

              const SizedBox(height: 48),

              // Role selection
              if (isReady) ...[
                const Text(
                  'Wähle deine Rolle:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),

                // Peripheral button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _selectRole(ChatRole.responder),
                    icon: const Icon(Icons.broadcast_on_personal),
                    label: const Text('Peripheral (Sichtbar machen)'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(20),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Werde sichtbar und warte auf Verbindungen',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),

                const SizedBox(height: 24),

                // Central button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _selectRole(ChatRole.initiator),
                    icon: const Icon(Icons.search),
                    label: const Text('Central (Suchen & Verbinden)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(20),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Suche nach sichtbaren Geräten und verbinde dich',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],

              if (!isReady && !_checking) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _checkPermissions,
                  child: const Text('Erneut prüfen'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Main chat screen that handles both Peripheral and Central roles
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.role});

  final ChatRole role;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<String> _log = [];
  final List<ChatMessage> _messages = [];
  final RelayRuntimeConfig _relayRuntimeConfig =
      RelayRuntimeConfig.fromEnvironment;

  // BLE components
  GattServer? _gattServer;
  GattClient? _gattClient;

  // Transport
  TransportEndpoint? _transport;
  RelayMailboxHttpClient? _relayMailboxClient;
  RelayWakeHttpClient? _relayWakeClient;
  RelayLink? _relayLink;
  RelayPollingLoop? _relayPollingLoop;
  RelayInboxStore? _relayInboxStore;
  RelayInboxQueue? _relayInboxQueue;
  RelayOutboxStore? _relayOutboxStore;
  RelayOutboxQueue? _relayOutboxQueue;
  final List<Uint8List> _pendingTransportPackets = [];
  bool _relayOutboxFlushInFlight = false;

  // Chat session
  ChatSession? _chatSession;
  PairingSession? _pairing;

  // Reconnect/pinning (central side optional)
  Uint8List? _expectedPeerStaticPubkeyX25519;
  bool _requireExpectedPeer = false;

  // State
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isAdvertising = false;
  BluetoothLowEnergyState? _bleState;
  String? _statusError;
  List<DiscoveredPeripheral> _discoveredDevices = [];

  // Subscriptions
  StreamSubscription<Uint8List>? _inboundSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<bool>? _advertisingSub;
  StreamSubscription<BluetoothLowEnergyState>? _bleStateSub;
  StreamSubscription<DiscoveredPeripheral>? _discoverySub;
  StreamSubscription<Uint8List>? _transportMessageSub;

  @override
  void initState() {
    super.initState();
    _logRelayConfig();
    _initBle();
  }

  Future<void> _initBle() async {
    _logLine('Initialisiere BLE als ${widget.role.name}...');

    try {
      if (widget.role == ChatRole.responder) {
        // Peripheral role: Start GATT Server
        _gattServer = GattServer(logger: _logLine);
        await _gattServer!.start();
        _isAdvertising = _gattServer!.isAdvertising;
        _bleState = _gattServer!.currentBleState;

        _connectionSub = _gattServer!.connectionState.listen((connected) {
          setState(() {
            _isConnected = connected;
            if (connected) {
              _statusError = null;
            }
          });
          if (connected) {
            _ensureTransport();
          } else {
            if (_relayLink == null) {
              _transport?.resetSession();
              _pairing?.reset();
              _chatSession = null;
              _expectedPeerStaticPubkeyX25519 = null;
              _requireExpectedPeer = false;
            } else {
              _logLine('BLE getrennt; Relay bleibt aktiv');
            }
          }
        });
        _advertisingSub = _gattServer!.advertisingState.listen((advertising) {
          if (!mounted) {
            _isAdvertising = advertising;
            return;
          }
          setState(() {
            _isAdvertising = advertising;
          });
        });
        _bleStateSub = _gattServer!.bleState.listen((state) {
          if (!mounted) {
            _bleState = state;
            return;
          }
          setState(() {
            _bleState = state;
          });
        });

        _logLine('GATT Server bereit');
      } else {
        // Central role: Initialize GATT Client
        _gattClient = GattClient(logger: _logLine);
        await _gattClient!.initialize();
        _bleState = _gattClient!.currentBleState;

        _connectionSub = _gattClient!.connectionState.listen((connected) {
          setState(() {
            _isConnected = connected;
            if (connected) {
              _statusError = null;
            }
          });
          if (connected) {
            _ensureTransport();
          } else {
            if (_relayLink == null) {
              _transport?.resetSession();
              _pairing?.reset();
              _chatSession = null;
              _expectedPeerStaticPubkeyX25519 = null;
              _requireExpectedPeer = false;
            } else {
              _logLine('BLE getrennt; Relay bleibt aktiv');
            }
          }
        });

        _discoverySub = _gattClient!.discovered.listen((device) {
          setState(() {
            // Avoid duplicates
            final exists = _discoveredDevices.any(
              (d) => d.peripheral.uuid == device.peripheral.uuid,
            );
            if (!exists) {
              _discoveredDevices.add(device);
            }
          });
        });
        _bleStateSub = _gattClient!.bleState.listen((state) {
          if (!mounted) {
            _bleState = state;
            return;
          }
          setState(() {
            _bleState = state;
          });
        });

        _logLine('GATT Client bereit');
      }
      await _initRelay();
      _ensureTransport();
    } catch (e) {
      _logLine('BLE Init Fehler: $e');
      _setStatusError('BLE Init Fehler');
    }
  }

  void _ensureTransport() {
    if (_transport != null) {
      return;
    }
    _logLine('Richte Transport ein...');

    final link = _buildHybridTransportLink();
    _transport = TransportEndpoint(
      name: widget.role.name,
      link: link,
      config: const TransportConfig(
        maxPayload: kMaxPayloadSize,
        ackTimeout: Duration(milliseconds: 500),
        maxRetries: 10,
      ),
      logger: _logLine,
    );

    _inboundSub?.cancel();
    // Listen for incoming BLE data and feed to transport.
    if (widget.role == ChatRole.responder) {
      _inboundSub = _gattServer!.inbound.listen((bytes) {
        _feedTransportPacket(bytes, source: 'BLE');
      });
    } else {
      _inboundSub = _gattClient!.inbound.listen((bytes) {
        _feedTransportPacket(bytes, source: 'BLE');
      });
    }

    if (_pendingTransportPackets.isNotEmpty) {
      _logLine(
        'Verarbeite ${_pendingTransportPackets.length} gepufferte Transportpakete...',
      );
      final pending = List<Uint8List>.from(_pendingTransportPackets);
      _pendingTransportPackets.clear();
      for (final packet in pending) {
        _transport!.handlePacket(packet);
      }
    }

    _transportMessageSub?.cancel();
    // Listen for assembled messages from transport
    _transportMessageSub = _transport!.messages.listen(_onTransportMessage);

    _logLine('Transport bereit');

    _pairing = PairingSession(
      role: widget.role,
      send: (bytes) => _transport!.sendMessage(bytes),
      onUpdate: () {
        if (!mounted) return;
        final pairing = _pairing;
        setState(() {
          if (pairing?.stage == PairingStage.failed) {
            _statusError = _statusErrorFromPairing(pairing?.error);
          } else if (pairing?.stage == PairingStage.established) {
            _statusError = null;
          }
        });
        if (pairing?.stage == PairingStage.established) {
          unawaited(_finalizeChatSessionFromPairing());
        }
      },
      expectedPeerStaticPubkeyX25519: _expectedPeerStaticPubkeyX25519,
      requireExpectedPeer: _requireExpectedPeer,
    );
    unawaited(_pairing!.startIfInitiator());
    unawaited(_flushRelayOutbox(reason: 'transport-ready'));
  }

  TransportLink _buildHybridTransportLink() {
    return _HybridTransportLink(
      resolveBleLink: _resolveBleTransportLink,
      preferBle: () => _isConnected,
      relayOutbox: _relayOutboxQueue,
      logger: _logLine,
    );
  }

  TransportLink? _resolveBleTransportLink() {
    if (widget.role == ChatRole.responder) {
      return _gattServer;
    }
    return _gattClient;
  }

  Future<void> _initRelay() async {
    if (!_relayRuntimeConfig.isRemoteAvailable) {
      _logLine('Relay deaktiviert: ${_relayRuntimeConfig.remoteStatusLabel}');
      return;
    }
    final baseUri = _relayRuntimeConfig.baseUri;
    if (baseUri == null) {
      _logLine('Relay deaktiviert: Base URL ungueltig');
      return;
    }
    final mailboxInbound = _relayRuntimeConfig.inboundMailboxId.trim();
    final mailboxOutbound = _relayRuntimeConfig.outboundMailboxId.trim();
    if (mailboxInbound.isEmpty || mailboxOutbound.isEmpty) {
      _logLine('Relay deaktiviert: Mailbox IDs fehlen');
      return;
    }

    try {
      final boxSuffix = widget.role.name;
      _relayInboxStore = await HiveRelayInboxStore.open(
        boxName: '${kRelayInboxBox}_$boxSuffix',
      );
      _relayOutboxStore = await HiveRelayOutboxStore.open(
        boxName: '${kRelayOutboxBox}_$boxSuffix',
      );
      _relayInboxQueue = RelayInboxQueue(store: _relayInboxStore!);

      _relayMailboxClient = RelayMailboxHttpClient(
        config: RelayLinkConfig(baseUri: baseUri),
        logger: _logLine,
      );
      final wakeSecret = _relayRuntimeConfig.wakeHmacSecret.trim();
      if (wakeSecret.isNotEmpty) {
        _relayWakeClient = RelayWakeHttpClient(
          config: RelayWakeConfig(baseUri: baseUri, hmacSecret: wakeSecret),
          logger: _logLine,
        );
      }
      final peerWakeToken = _relayRuntimeConfig.peerWakeToken.trim();
      _relayLink = RelayLink(
        client: _relayMailboxClient!,
        outboundMailboxId: mailboxOutbound,
        inboundMailboxId: mailboxInbound,
        inboxQueue: _relayInboxQueue,
        wakeClient: _relayWakeClient,
        peerWakeToken: peerWakeToken.isEmpty ? null : peerWakeToken,
        onInboundCiphertext: (bytes) {
          _feedTransportPacket(bytes, source: 'Relay');
        },
        onWakeResult: (result) {
          _logLine('Relay Wake: ${result.status}');
        },
        onWakeError: (error, _) {
          _logLine('Relay Wake Fehler: $error');
        },
      );
      _relayOutboxQueue = RelayOutboxQueue(
        store: _relayOutboxStore!,
        sender: ({required ciphertext, required clientMsgId}) {
          return _relayLink!.pushCiphertext(
            ciphertext,
            clientMsgId: clientMsgId,
          );
        },
      );
      _relayPollingLoop = RelayPollingLoop(
        link: _relayLink!,
        onPoll: (result) {
          final pulledCount = result.pull.messages.length;
          if (pulledCount > 0 || result.pull.hasMore) {
            _logLine(
              'Relay poll: pulled=$pulledCount hasMore=${result.pull.hasMore}',
            );
          }
          unawaited(_flushRelayOutbox(reason: 'poll'));
        },
        onError: (error, _) {
          _logLine('Relay poll Fehler: $error');
        },
        logger: _logLine,
      );
      _relayPollingLoop!.start();
      _logLine(
        'Relay aktiv: in=$mailboxInbound out=$mailboxOutbound base=${baseUri.host}',
      );
      unawaited(_flushRelayOutbox(reason: 'relay-init'));
    } catch (e) {
      _logLine('Relay Init Fehler: $e');
      _setStatusError('Relay Initialisierung fehlgeschlagen');
    }
  }

  void _feedTransportPacket(Uint8List bytes, {required String source}) {
    final transport = _transport;
    if (transport == null) {
      _pendingTransportPackets.add(Uint8List.fromList(bytes));
      _logLine('$source RX gepuffert (${_pendingTransportPackets.length})');
      return;
    }
    transport.handlePacket(bytes);
  }

  Future<void> _flushRelayOutbox({required String reason}) async {
    final outbox = _relayOutboxQueue;
    if (outbox == null || _relayOutboxFlushInFlight) {
      return;
    }
    _relayOutboxFlushInFlight = true;
    try {
      final result = await outbox.flushPending(limit: 20);
      if (result.processed > 0) {
        _logLine(
          'Relay Outbox[$reason]: processed=${result.processed} sent=${result.sent} retry=${result.retryScheduled} failed=${result.failed}',
        );
      }
    } catch (e) {
      _logLine('Relay Outbox Flush Fehler[$reason]: $e');
    } finally {
      _relayOutboxFlushInFlight = false;
    }
  }

  Future<void> _disposeRelay() async {
    final loop = _relayPollingLoop;
    _relayPollingLoop = null;
    if (loop != null) {
      await loop.stop();
    }
    _relayLink?.close(force: true);
    _relayLink = null;
    _relayMailboxClient = null;
    _relayWakeClient = null;
    await _relayInboxStore?.close();
    _relayInboxStore = null;
    await _relayOutboxStore?.close();
    _relayOutboxStore = null;
    _relayInboxQueue = null;
    _relayOutboxQueue = null;
  }

  Future<void> _onTransportMessage(Uint8List data) async {
    if (_pairing != null) {
      final consumed = await _pairing!.handleIncoming(data);
      if (consumed) {
        if (_pairing!.stage == PairingStage.failed) {
          _logLine('Pairing Fehler: ${_pairing!.error}');
          _setStatusError(_statusErrorFromPairing(_pairing!.error));
        }
        return;
      }
    }

    _logLine('Nachricht empfangen: ${data.length} bytes');
    try {
      final session = _chatSession;
      if (session == null) {
        _logLine('Ignoriere Nachricht (noch kein Secure Session)');
        return;
      }
      final result = await session.decryptFrame(data);
      _logLine('Entschlüsselt: ${result.message.bodyUtf8}');
      setState(() {
        _messages.add(result.message);
      });
    } catch (e) {
      _logLine('Decrypt Fehler: $e');
      _setStatusError('Entschluesselung fehlgeschlagen');
    }
  }

  Future<void> _finalizeChatSessionFromPairing() async {
    final pairing = _pairing;
    if (pairing == null) return;
    if (pairing.stage != PairingStage.established) return;
    if (pairing.masterKey32 == null ||
        pairing.sessionId4 == null ||
        pairing.keyId == null)
      return;

    final resolvedContactId = pairing.contactId ?? 'peer';
    final resolvedKeyId = pairing.keyId!;
    final resolvedSessionId = Uint8List.fromList(pairing.sessionId4!);
    final sessionIdData = ByteData.sublistView(resolvedSessionId);
    final sessionIdInt = sessionIdData.getUint32(0, Endian.little);

    final existing = _chatSession;
    if (existing != null &&
        existing.contactId == resolvedContactId &&
        existing.keyId == resolvedKeyId &&
        _bytesEqual(existing.sessionIdBytes, resolvedSessionId)) {
      return;
    }

    final counterState = await ChatStorage.instance.ensureSessionCounterState(
      contactId: resolvedContactId,
      keyId: resolvedKeyId,
      sessionId: sessionIdInt,
    );
    if (!mounted) return;
    if (_pairing != pairing || pairing.stage != PairingStage.established)
      return;

    final session = ChatSession(
      contactId: resolvedContactId,
      sessionId: resolvedSessionId,
      keyId: resolvedKeyId,
      masterKey: pairing.masterKey32!,
      role: widget.role,
      txCounter: counterState.nextTxCounter,
      lastRxCounter: counterState.lastRxCounter,
      rxSeenWindowBits: counterState.rxSeenWindowBits,
      reserveTxCounter: () => ChatStorage.instance.reserveNextTxCounter(
        contactId: resolvedContactId,
        keyId: resolvedKeyId,
        sessionId: sessionIdInt,
      ),
      commitRxCounter: (counter) => ChatStorage.instance.commitLastRxCounter(
        contactId: resolvedContactId,
        keyId: resolvedKeyId,
        sessionId: sessionIdInt,
        counter: counter,
      ),
    );
    setState(() {
      _chatSession = session;
    });
    _logLine(
      'Secure session bereit (contactId=$resolvedContactId, keyId=$resolvedKeyId)',
    );
  }

  String _hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString().toUpperCase();
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Peripheral actions
  Future<void> _startAdvertising() async {
    if (_gattServer == null) return;

    try {
      await _gattServer!.startAdvertising(name: 'PRSM');
      setState(() => _isAdvertising = true);
      _logLine('Advertising gestartet');
      _setStatusError(null);
    } catch (e) {
      _logLine('Advertising Fehler: $e');
      _setStatusError('Advertising fehlgeschlagen');
    }
  }

  Future<void> _stopAdvertising() async {
    if (_gattServer == null) return;

    await _gattServer!.stopAdvertising();
    setState(() => _isAdvertising = false);
    _logLine('Advertising gestoppt');
    _setStatusError(null);
  }

  // Central actions
  Future<void> _startScan() async {
    if (_gattClient == null) return;

    setState(() {
      _discoveredDevices.clear();
      _isScanning = true;
    });

    try {
      await _gattClient!.startScan();
      _logLine('Scan gestartet');
      _setStatusError(null);
    } catch (e) {
      _logLine('Scan Fehler: $e');
      setState(() => _isScanning = false);
      _setStatusError('Scan fehlgeschlagen');
    }
  }

  Future<void> _stopScan() async {
    if (_gattClient == null) return;

    await _gattClient!.stopScan();
    setState(() => _isScanning = false);
    _logLine('Scan gestoppt');
    _setStatusError(null);
  }

  Future<void> _connectTo(DiscoveredPeripheral device) async {
    if (_gattClient == null) return;

    final expected = await _promptExpectedPeerForReconnect();
    if (!mounted) return;
    setState(() {
      _expectedPeerStaticPubkeyX25519 = expected?.staticPubkey32;
      _requireExpectedPeer = expected != null;
    });

    _logLine('Verbinde zu ${device.name ?? device.peripheral.uuid}...');

    try {
      await _gattClient!.connect(device.peripheral);
      _logLine('Verbunden!');
      _setStatusError(null);
    } catch (e) {
      _logLine('Verbindung fehlgeschlagen: $e');
      _setStatusError('Verbindung fehlgeschlagen');
    }
  }

  Future<_ExpectedPeer?> _promptExpectedPeerForReconnect() async {
    if (widget.role != ChatRole.initiator) return null;

    final contacts =
        ChatStorage.instance.contactsBox.values
            .where(
              (c) => c.trusted && !c.blocked && (c.staticPubkey?.length == 32),
            )
            .toList()
          ..sort((a, b) => a.nickname.compareTo(b.nickname));

    if (contacts.isEmpty) return null;

    return showDialog<_ExpectedPeer?>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Sicher verbinden'),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Für bekannte Kontakte kann Reconnect ohne SAS erfolgen (Pinning).',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Neues Pairing (SAS vergleichen)'),
            ),
            ...contacts.map((c) {
              return SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(
                  _ExpectedPeer(
                    contactId: c.contactId,
                    nickname: c.nickname,
                    staticPubkey32: Uint8List.fromList(c.staticPubkey!),
                  ),
                ),
                child: Text('Reconnect: ${c.nickname}'),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _disconnect() async {
    if (widget.role == ChatRole.initiator) {
      await _gattClient?.disconnect();
    }
    // For peripheral, we can't force disconnect in MVP

    _transport?.resetSession();
    _pairing?.reset();
    _chatSession = null;
    _expectedPeerStaticPubkeyX25519 = null;
    _requireExpectedPeer = false;

    setState(() {
      _isConnected = false;
      _statusError = null;
    });
    _logLine('Getrennt');
    if (_relayLink != null && _pairing != null) {
      unawaited(_pairing!.startIfInitiator());
    }
  }

  // Messaging
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _transport == null) return;
    if (_chatSession == null) {
      _logLine('Noch nicht bereit: Pairing abschliessen');
      _setStatusError('Pairing noch nicht abgeschlossen');
      return;
    }

    _messageController.clear();

    try {
      final result = await _chatSession!.encryptText(body: text);
      setState(() {
        _messages.add(result.message);
      });
      _logLine('Verschlüsselt: ${result.frame.length} bytes');

      await _transport!.sendMessage(result.frame);
      _logLine('Gesendet!');
      _setStatusError(null);

      // Update status
      _updateMessageStatus(result.message.messageId, MessageStatus.sent);
    } catch (e) {
      _logLine('Senden fehlgeschlagen: $e');
      _setStatusError('Senden fehlgeschlagen');
    }
  }

  void _updateMessageStatus(String messageId, int status) {
    final index = _messages.indexWhere((m) => m.messageId == messageId);
    if (index == -1) return;

    final msg = _messages[index];
    setState(() {
      _messages[index] = ChatMessage(
        messageId: msg.messageId,
        conversationId: msg.conversationId,
        direction: msg.direction,
        status: status,
        sentAtMs: msg.sentAtMs,
        receivedAtMs: msg.receivedAtMs,
        bodyUtf8: msg.bodyUtf8,
        keyId: msg.keyId,
        counter: msg.counter,
        sessionId: msg.sessionId,
      );
    });
  }

  void _setStatusError(String? message) {
    if (!mounted) {
      _statusError = message;
      return;
    }
    setState(() {
      _statusError = message;
    });
  }

  bool _isSilentDowngradeBlocked(PairingSession? pairing) {
    if (pairing == null || pairing.stage != PairingStage.failed) {
      return false;
    }
    final error = pairing.error;
    if (error == null) {
      return false;
    }
    return error.contains('silent downgrade');
  }

  String _statusErrorFromPairing(String? error) {
    if (error == null || error.isEmpty) {
      return 'Pairing fehlgeschlagen';
    }
    if (error.contains('silent downgrade')) {
      return 'Sicherheitsabbruch: stilles Downgrade blockiert';
    }
    return 'Pairing Fehler: $error';
  }

  String _trustLabel(PairingSession? pairing) {
    if (pairing == null) {
      return 'untrusted';
    }
    if (pairing.stage == PairingStage.established) {
      return pairing.trustedReconnect ? 'trusted (reconnect)' : 'trusted (neu)';
    }
    return 'untrusted';
  }

  Widget _buildStatusPill({
    required IconData icon,
    required String text,
    required Color color,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  void _logLine(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    debugPrint('$stamp $message');
    setState(() {
      _log.insert(0, '$stamp $message');
      if (_log.length > 100) {
        _log.removeRange(100, _log.length);
      }
    });
  }

  @override
  void dispose() {
    _inboundSub?.cancel();
    _connectionSub?.cancel();
    _advertisingSub?.cancel();
    _bleStateSub?.cancel();
    _discoverySub?.cancel();
    _transportMessageSub?.cancel();
    unawaited(_disposeRelay());
    _gattServer?.dispose();
    _gattClient?.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPeripheral = widget.role == ChatRole.responder;
    final roleLabel = isPeripheral ? 'Peripheral' : 'Central';

    return Scaffold(
      appBar: AppBar(
        title: Text('PRSM Chat ($roleLabel)'),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _disconnect,
              tooltip: 'Trennen',
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection status bar
          _buildStatusBar(),

          // Main content
          Expanded(
            child:
                (_isConnected ||
                    (_relayLink != null &&
                        (_pairing != null || _chatSession != null)))
                ? _buildChatView()
                : _buildConnectionView(),
          ),

          // Log section
          _buildLogSection(),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final pairing = _pairing;
    final pairingLabel = pairing == null
        ? null
        : switch (pairing.stage) {
            PairingStage.idle => 'Pairing: idle',
            PairingStage.handshaking => 'Pairing: handshake…',
            PairingStage.sasReady => 'Pairing: SAS',
            PairingStage.waitingPeerSas => 'Pairing: warte Peer…',
            PairingStage.waitingMasterKey => 'Pairing: warte Key…',
            PairingStage.waitingMasterKeyAck => 'Pairing: warte ACK…',
            PairingStage.waitingMasterKeyCommit => 'Pairing: warte Commit…',
            PairingStage.established =>
              pairing.trustedReconnect
                  ? 'Reconnect: sicher'
                  : 'Pairing: sicher',
            PairingStage.failed => 'Pairing: FEHLER',
          };
    final silentDowngradeBlocked = _isSilentDowngradeBlocked(pairing);
    final remoteAvailable = _relayRuntimeConfig.isRemoteAvailable;
    final remoteStatusLabel = _relayRuntimeConfig.remoteStatusLabel;
    final trustLabel = _trustLabel(pairing);
    final statusError = _statusError;
    final connectionLabel = _connectionStatusLabel();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _isConnected
          ? (_chatSession != null
                ? Colors.green.shade100
                : Colors.yellow.shade100)
          : Colors.orange.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_searching,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  connectionLabel,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildStatusPill(
                icon: remoteAvailable ? Icons.cloud_done : Icons.cloud_off,
                text: remoteAvailable
                    ? 'Relay aktiv'
                    : 'Relay optional (nicht konfiguriert)',
                color: remoteAvailable
                    ? Colors.green.shade50
                    : Colors.blueGrey.shade50,
                foreground: remoteAvailable
                    ? Colors.green.shade800
                    : Colors.blueGrey.shade800,
              ),
              if (!remoteAvailable)
                _buildStatusPill(
                  icon: Icons.info_outline,
                  text: remoteStatusLabel,
                  color: Colors.orange.shade50,
                  foreground: Colors.orange.shade900,
                ),
              _buildStatusPill(
                icon: trustLabel.startsWith('trusted')
                    ? Icons.verified_user
                    : Icons.gpp_maybe,
                text: 'Trust: $trustLabel',
                color: trustLabel.startsWith('trusted')
                    ? Colors.teal.shade50
                    : Colors.blueGrey.shade50,
                foreground: trustLabel.startsWith('trusted')
                    ? Colors.teal.shade900
                    : Colors.blueGrey.shade900,
              ),
              if (_isConnected && pairingLabel != null)
                _buildStatusPill(
                  icon: Icons.lock_clock,
                  text: pairingLabel,
                  color: Colors.blue.shade50,
                  foreground: Colors.blue.shade900,
                ),
              if (silentDowngradeBlocked)
                _buildStatusPill(
                  icon: Icons.gpp_bad,
                  text: 'Kein stilles Downgrade (blockiert)',
                  color: Colors.red.shade50,
                  foreground: Colors.red.shade900,
                ),
              if (statusError != null)
                _buildStatusPill(
                  icon: Icons.error_outline,
                  text: statusError,
                  color: Colors.red.shade50,
                  foreground: Colors.red.shade900,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _connectionStatusLabel() {
    final bleState = _bleState;
    if (bleState != null && bleState != BluetoothLowEnergyState.poweredOn) {
      if (bleState == BluetoothLowEnergyState.poweredOff) {
        return 'Bluetooth aus';
      }
      if (bleState == BluetoothLowEnergyState.unauthorized) {
        return 'Bluetooth nicht erlaubt';
      }
      return 'Bluetooth nicht bereit ($bleState)';
    }
    if (_isConnected) {
      return _chatSession != null
          ? 'Verbunden (Secure)'
          : 'Verbunden (Pairing)';
    }
    if (widget.role == ChatRole.responder) {
      if (_isAdvertising && _relayLink != null) {
        return 'Bluetooth aktiv (Advertising) · Relay aktiv · kein Peer';
      }
      if (_isAdvertising) {
        return 'Bluetooth aktiv (Advertising) · kein Peer verbunden';
      }
      if (_gattServer?.isRunning == true && _relayLink != null) {
        return 'Bluetooth aktiv · Relay aktiv · nicht verbunden';
      }
      if (_gattServer?.isRunning == true) {
        return 'Bluetooth aktiv · nicht verbunden';
      }
    }
    if (_gattClient != null && _relayLink != null) {
      return 'Bluetooth aktiv · Relay aktiv · nicht verbunden';
    }
    if (_gattClient != null) {
      return 'Bluetooth aktiv · nicht verbunden';
    }
    if (_relayLink != null) {
      return 'Relay aktiv · Bluetooth nicht verbunden';
    }
    return 'Nicht verbunden';
  }

  void _logRelayConfig() {
    final baseUri = _relayRuntimeConfig.baseUri;
    final relayEndpoint = baseUri == null
        ? '<nicht gesetzt>'
        : '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}';
    _logLine(
      'Relay-Konfig: endpoint=$relayEndpoint, mailboxIds=${_relayRuntimeConfig.hasMailboxIds ? 'ok' : 'fehlen'}, wake=${_relayRuntimeConfig.isWakeConfigured ? 'ja' : 'nein'}',
    );
  }

  Widget _buildConnectionView() {
    if (widget.role == ChatRole.responder) {
      // Peripheral: Show advertising controls
      return _buildPeripheralView();
    } else {
      // Central: Show scan results
      return _buildCentralView();
    }
  }

  Widget _buildPeripheralView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GATT Server', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Starte Advertising, damit andere Geräte dich finden können.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isAdvertising ? null : _startAdvertising,
                icon: const Icon(Icons.broadcast_on_personal),
                label: const Text('Advertise'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _isAdvertising ? _stopAdvertising : null,
                child: const Text('Stop'),
              ),
              const SizedBox(width: 12),
              if (_isAdvertising)
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Warte auf Verbindung...'),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCentralView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Geräte suchen', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: const Icon(Icons.search),
                label: const Text('Scan'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _isScanning ? _stopScan : null,
                child: const Text('Stop'),
              ),
              const SizedBox(width: 12),
              if (_isScanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: _discoveredDevices.isEmpty
                ? const Center(
                    child: Text(
                      'Keine Geräte gefunden.\nStarte einen Scan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _discoveredDevices.length,
                    itemBuilder: (context, index) {
                      final device = _discoveredDevices[index];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.name ?? 'Unbekannt'),
                        subtitle: Text('RSSI: ${device.rssi}'),
                        trailing: ElevatedButton(
                          onPressed: () => _connectTo(device),
                          child: const Text('Verbinden'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatView() {
    final pairing = _pairing;
    final sasVisible =
        pairing != null &&
        (pairing.stage == PairingStage.sasReady ||
            pairing.stage == PairingStage.waitingPeerSas ||
            pairing.stage == PairingStage.waitingMasterKey ||
            pairing.stage == PairingStage.waitingMasterKeyAck ||
            pairing.stage == PairingStage.waitingMasterKeyCommit);
    final needsSasConfirm =
        sasVisible && !pairing!.localSasConfirmed && !pairing.trustedReconnect;
    final sessionIdLabel = _chatSession == null
        ? null
        : _hex(_chatSession!.sessionIdBytes);

    return Column(
      children: [
        // Encryption banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: _chatSession != null
              ? Colors.teal.shade50
              : Colors.blueGrey.shade50,
          child: Row(
            children: [
              Icon(
                Icons.lock,
                size: 16,
                color: _chatSession != null
                    ? Colors.teal.shade700
                    : Colors.blueGrey.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _chatSession != null
                      ? 'Ende-zu-Ende verschlüsselt • Session $sessionIdLabel'
                      : (pairing == null
                            ? 'Pairing initialisiert…'
                            : 'Pairing: ${pairing.stage.name}${pairing.error != null ? " (${pairing.error})" : ""}'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _chatSession != null
                        ? Colors.teal.shade800
                        : Colors.blueGrey.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (sasVisible)
          Container(
            width: double.infinity,
            color: Colors.blueGrey.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    pairing.trustedReconnect
                        ? 'Reconnect: verifiziert (Pinning)'
                        : 'SAS: ${pairing.sas ?? "…"}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (needsSasConfirm)
                  ElevatedButton(
                    onPressed: () => unawaited(pairing.confirmSas()),
                    child: const Text('Stimmt'),
                  )
                else
                  const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),

        // Messages
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text(
                    'Noch keine Nachrichten.\nSende eine verschlüsselte Nachricht!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = msg.direction == MessageDirection.outbound;
                    return _buildMessageBubble(msg, isMe);
                  },
                ),
        ),

        // Input
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: _chatSession != null,
                    decoration: const InputDecoration(
                      hintText: 'Nachricht eingeben...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.teal.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(msg.bodyUtf8),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg.sentAtMs),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.status == MessageStatus.sent
                        ? Icons.check
                        : msg.status == MessageStatus.failed
                        ? Icons.error_outline
                        : Icons.schedule,
                    size: 12,
                    color: msg.status == MessageStatus.failed
                        ? Colors.red
                        : Colors.grey,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int millis) {
    if (millis == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildLogSection() {
    return ExpansionTile(
      title: const Text('Log'),
      initiallyExpanded: false,
      children: [
        Container(
          height: 150,
          padding: const EdgeInsets.all(8),
          color: Colors.grey.shade100,
          child: ListView.builder(
            itemCount: _log.length,
            itemBuilder: (context, index) => Text(
              _log[index],
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpectedPeer {
  _ExpectedPeer({
    required this.contactId,
    required this.nickname,
    required this.staticPubkey32,
  });

  final String contactId;
  final String nickname;
  final Uint8List staticPubkey32;
}

class _HybridTransportLink implements TransportLink {
  _HybridTransportLink({
    required this.resolveBleLink,
    required this.preferBle,
    required this.relayOutbox,
    required this.logger,
  });

  final TransportLink? Function() resolveBleLink;
  final bool Function() preferBle;
  final RelayOutboxQueue? relayOutbox;
  final void Function(String message) logger;

  @override
  Future<void> send(Uint8List bytes) async {
    final ble = resolveBleLink();
    if (preferBle() && ble != null) {
      try {
        await ble.send(bytes);
        return;
      } catch (e) {
        logger('HybridLink: BLE send fehlgeschlagen, fallback Relay: $e');
      }
    }

    final outbox = relayOutbox;
    if (outbox != null) {
      final entry = await outbox.enqueue(ciphertext: bytes);
      final flush = await outbox.flushPending(limit: 1);
      if (flush.sent > 0 || flush.retryScheduled > 0) {
        return;
      }
      throw StateError(
        'Relay send fehlgeschlagen (clientMsgId=${entry.clientMsgId})',
      );
    }

    if (ble != null) {
      await ble.send(bytes);
      return;
    }

    throw StateError('Kein aktiver BLE- oder Relay-Link verfügbar');
  }
}
