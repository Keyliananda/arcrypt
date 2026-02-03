import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble/ble.dart';
import 'chat/chat.dart';
import 'transport/transport.dart';

void main() {
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
  final CentralManager _centralManager = CentralManager();
  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;

  @override
  void initState() {
    super.initState();
    _setupBleStateListener();
    _checkPermissions();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  void _setupBleStateListener() {
    // Listen for BLE state changes (important for iOS!)
    _stateSub = _centralManager.stateChanged.listen((event) {
      _updateBleState(event.state);
    });
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
        _status = 'Bluetooth-Berechtigung fehlt.\nBitte in den Einstellungen erlauben.';
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
        _status = 'Bluetooth-Berechtigungen fehlen.\nBitte in den Einstellungen erlauben.';
      });
      return;
    }

    // Check current BLE state
    // On iOS, accessing .state may trigger the permission dialog
    final currentState = _centralManager.state;
    _updateBleState(currentState);
    
    // If state is unknown, wait a moment for iOS to update
    if (currentState == BluetoothLowEnergyState.unknown) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _updateBleState(_centralManager.state);
      }
    }
  }

  void _selectRole(ChatRole role) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(role: role),
      ),
    );
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
              const SizedBox(height: 32),

              // Status
              if (_checking)
                const CircularProgressIndicator()
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isReady ? Colors.green.shade50 : Colors.orange.shade50,
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
                      Text(_status),
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

/// Shared test key (32 bytes) - same on all devices for this spike
final Uint8List kTestMasterKey = Uint8List.fromList([
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
  0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
  0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
  0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
]);

/// Shared session ID (4 bytes)
final Uint8List kTestSessionId = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<String> _log = [];
  final List<ChatMessage> _messages = [];

  // BLE components
  GattServer? _gattServer;
  GattClient? _gattClient;

  // Transport
  TransportEndpoint? _transport;

  // Chat session
  late ChatSession _chatSession;

  // State
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isAdvertising = false;
  List<DiscoveredPeripheral> _discoveredDevices = [];

  // Subscriptions
  StreamSubscription<Uint8List>? _inboundSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<DiscoveredPeripheral>? _discoverySub;
  StreamSubscription<Uint8List>? _transportMessageSub;

  @override
  void initState() {
    super.initState();
    _initChatSession();
    _initBle();
  }

  void _initChatSession() {
    _chatSession = ChatSession(
      contactId: 'test-peer',
      sessionId: kTestSessionId,
      keyId: 'test-key',
      masterKey: kTestMasterKey,
      role: widget.role,
    );
  }

  Future<void> _initBle() async {
    _logLine('Initialisiere BLE als ${widget.role.name}...');

    try {
      if (widget.role == ChatRole.responder) {
        // Peripheral role: Start GATT Server
        _gattServer = GattServer(logger: _logLine);
        await _gattServer!.start();
        
        _connectionSub = _gattServer!.connectionState.listen((connected) {
          setState(() => _isConnected = connected);
          if (connected) {
            _setupTransport(_gattServer!);
          }
        });

        _logLine('GATT Server bereit');
      } else {
        // Central role: Initialize GATT Client
        _gattClient = GattClient(logger: _logLine);
        await _gattClient!.initialize();
        
        _connectionSub = _gattClient!.connectionState.listen((connected) {
          setState(() => _isConnected = connected);
          if (connected) {
            _setupTransport(_gattClient!);
          } else {
            _transport?.resetSession();
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

        _logLine('GATT Client bereit');
      }
    } catch (e) {
      _logLine('BLE Init Fehler: $e');
    }
  }

  void _setupTransport(TransportLink link) {
    _logLine('Richte Transport ein...');

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

    // Listen for incoming BLE data and feed to transport
    if (widget.role == ChatRole.responder) {
      _inboundSub = _gattServer!.inbound.listen((bytes) {
        _transport!.handlePacket(bytes);
      });
    } else {
      _inboundSub = _gattClient!.inbound.listen((bytes) {
        _transport!.handlePacket(bytes);
      });
    }

    // Listen for assembled messages from transport
    _transportMessageSub = _transport!.messages.listen(_onTransportMessage);

    _logLine('Transport bereit');
  }

  Future<void> _onTransportMessage(Uint8List data) async {
    _logLine('Nachricht empfangen: ${data.length} bytes');
    try {
      final result = await _chatSession.decryptFrame(data);
      _logLine('Entschlüsselt: ${result.message.bodyUtf8}');
      setState(() {
        _messages.add(result.message);
      });
    } catch (e) {
      _logLine('Decrypt Fehler: $e');
    }
  }

  // Peripheral actions
  Future<void> _startAdvertising() async {
    if (_gattServer == null) return;
    
    try {
      await _gattServer!.startAdvertising(name: 'PRSM');
      setState(() => _isAdvertising = true);
      _logLine('Advertising gestartet');
    } catch (e) {
      _logLine('Advertising Fehler: $e');
    }
  }

  Future<void> _stopAdvertising() async {
    if (_gattServer == null) return;
    
    await _gattServer!.stopAdvertising();
    setState(() => _isAdvertising = false);
    _logLine('Advertising gestoppt');
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
    } catch (e) {
      _logLine('Scan Fehler: $e');
      setState(() => _isScanning = false);
    }
  }

  Future<void> _stopScan() async {
    if (_gattClient == null) return;
    
    await _gattClient!.stopScan();
    setState(() => _isScanning = false);
    _logLine('Scan gestoppt');
  }

  Future<void> _connectTo(DiscoveredPeripheral device) async {
    if (_gattClient == null) return;
    
    _logLine('Verbinde zu ${device.name ?? device.peripheral.uuid}...');
    
    try {
      await _gattClient!.connect(device.peripheral);
      _logLine('Verbunden!');
    } catch (e) {
      _logLine('Verbindung fehlgeschlagen: $e');
    }
  }

  Future<void> _disconnect() async {
    if (widget.role == ChatRole.initiator) {
      await _gattClient?.disconnect();
    }
    // For peripheral, we can't force disconnect in MVP
    
    await _inboundSub?.cancel();
    await _transportMessageSub?.cancel();
    _transport?.resetSession();
    
    setState(() => _isConnected = false);
    _logLine('Getrennt');
  }

  // Messaging
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _transport == null) return;

    _messageController.clear();

    try {
      final result = await _chatSession.encryptText(body: text);
      setState(() {
        _messages.add(result.message);
      });
      _logLine('Verschlüsselt: ${result.frame.length} bytes');

      await _transport!.sendMessage(result.frame);
      _logLine('Gesendet!');
      
      // Update status
      _updateMessageStatus(result.message.messageId, MessageStatus.sent);
    } catch (e) {
      _logLine('Senden fehlgeschlagen: $e');
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

  void _logLine(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
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
    _discoverySub?.cancel();
    _transportMessageSub?.cancel();
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
            child: _isConnected ? _buildChatView() : _buildConnectionView(),
          ),

          // Log section
          _buildLogSection(),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _isConnected ? Colors.green.shade100 : Colors.orange.shade100,
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isConnected ? 'Verbunden' : 'Nicht verbunden',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
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
                      width: 16, height: 16,
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
                  width: 16, height: 16,
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
    return Column(
      children: [
        // Encryption banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.teal.shade50,
          child: Row(
            children: [
              Icon(Icons.lock, size: 16, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ende-zu-Ende verschlüsselt • Session DEADBEEF',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.teal.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                    decoration: const InputDecoration(
                      hintText: 'Nachricht eingeben...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
