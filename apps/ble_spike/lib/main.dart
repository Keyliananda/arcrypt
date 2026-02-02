import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'chat/chat.dart';
import 'transport/transport.dart';

void main() {
  runApp(const BleSpikeApp());
}

class BleSpikeApp extends StatelessWidget {
  const BleSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Chat Spike',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const BleChatHome(),
    );
  }
}

class BleChatHome extends StatefulWidget {
  const BleChatHome({super.key});

  @override
  State<BleChatHome> createState() => _BleChatHomeState();
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

const String kChatServiceUuid = 'F00D0001-1212-EFDE-1523-785FEABCD123';

class _BleChatHomeState extends State<BleChatHome> {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final TextEditingController _messageController = TextEditingController();

  final List<String> _log = <String>[];
  final List<_ChatBubble> _messages = <_ChatBubble>[];

  List<ScanResult> _scanResults = <ScanResult>[];
  bool _isScanning = false;
  bool _isAdvertising = false;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  // Transport layer
  late _BleTransportLink _transportLink;
  late TransportEndpoint _transport;
  StreamSubscription<Uint8List>? _transportMessageSub;

  // Chat session
  late ChatSession _chatSession;
  bool _isInitiator = false; // Set when connecting/accepting

  @override
  void initState() {
    super.initState();
    _initTransport();

    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    });
    _isScanningSub = FlutterBluePlus.isScanning.listen((value) {
      setState(() {
        _isScanning = value;
      });
    });
  }

  void _initTransport() {
    _transportLink = _BleTransportLink(sendCallback: _sendRawBytes);
    _transport = TransportEndpoint(
      name: 'local',
      link: _transportLink,
      config: const TransportConfig(
        maxPayload: 180, // BLE MTU - overhead
        ackTimeout: Duration(milliseconds: 500),
        maxRetries: 10,
      ),
      logger: _logLine,
    );

    _transportMessageSub = _transport.messages.listen(_onTransportMessage);

    // Default to initiator, will be adjusted on connect
    _chatSession = ChatSession(
      contactId: 'test-peer',
      sessionId: kTestSessionId,
      keyId: 'test-key',
      masterKey: kTestMasterKey,
      role: ChatRole.initiator,
    );
  }

  void _setRole(ChatRole role) {
    _chatSession = ChatSession(
      contactId: 'test-peer',
      sessionId: kTestSessionId,
      keyId: 'test-key',
      masterKey: kTestMasterKey,
      role: role,
    );
    _isInitiator = role == ChatRole.initiator;
    _logLine('Role set to: ${role.name}');
  }

  @override
  void dispose() {
    _scanResultsSub?.cancel();
    _isScanningSub?.cancel();
    _notifySub?.cancel();
    _connectionSub?.cancel();
    _transportMessageSub?.cancel();
    _messageController.dispose();
    super.dispose();
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

  void _addMessage(String text, bool isMe) {
    setState(() {
      _messages.add(_ChatBubble(text: text, isMe: isMe));
    });
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) {
      _logLine('iOS: Permissions automatisch.');
      return;
    }

    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();

    _logLine('Permissions: ${statuses.values.map((s) => s.name).join(', ')}');
  }

  Future<void> _startScan() async {
    setState(() {
      _scanResults = <ScanResult>[];
    });
    _logLine('Scan gestartet...');
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 30),
      withServices: [Guid(kChatServiceUuid)],
    );
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    _logLine('Scan gestoppt.');
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _logLine('Verbinde zu ${device.remoteId}...');
    _setRole(ChatRole.initiator); // We are initiating the connection

    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      _logLine('Verbunden!');

      _connectionSub = device.connectionState.listen((state) {
        _logLine('Connection state: $state');
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      final services = await device.discoverServices();
      _logLine('${services.length} Services gefunden');

      for (final service in services) {
        if (service.uuid.toString().toUpperCase().contains('F00D0001')) {
          _logLine('Chat Service gefunden!');
          for (final char in service.characteristics) {
            final uuid = char.uuid.toString().toUpperCase();
            if (uuid.contains('F00D0002')) {
              _writeChar = char;
              _logLine('Write Char gefunden');
            } else if (uuid.contains('F00D0003')) {
              _notifyChar = char;
              _logLine('Notify Char gefunden');
            }
          }
        }
      }

      if (_notifyChar != null) {
        await _notifyChar!.setNotifyValue(true);
        _notifySub = _notifyChar!.onValueReceived.listen(_onBytesReceived);
        _logLine('Notifications aktiviert');
      }

      setState(() {});
      _logLine('Bereit zum Chatten!');
    } catch (e) {
      _logLine('Verbindungsfehler: $e');
    }
  }

  void _onDisconnected() {
    _logLine('Verbindung getrennt');
    setState(() {
      _connectedDevice = null;
      _writeChar = null;
      _notifyChar = null;
    });
    _notifySub?.cancel();
    _connectionSub?.cancel();
    _transport.resetSession();
  }

  Future<void> _disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _onDisconnected();
  }

  void _onBytesReceived(List<int> value) {
    final bytes = Uint8List.fromList(value);
    _logLine('RX ${bytes.length} bytes');
    _transport.handlePacket(bytes);
  }

  void _sendRawBytes(Uint8List bytes) {
    if (_writeChar == null) {
      _logLine('Kein Write-Char!');
      return;
    }
    _logLine('TX ${bytes.length} bytes');
    _writeChar!.write(bytes.toList(), withoutResponse: false);
  }

  Future<void> _onTransportMessage(Uint8List data) async {
    _logLine('Transport: ${data.length} bytes empfangen');
    try {
      final result = await _chatSession.decryptFrame(data);
      _logLine('Entschlüsselt: ${result.message.bodyUtf8}');
      _addMessage(result.message.bodyUtf8, false);
    } catch (e) {
      _logLine('Decrypt Fehler: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    _addMessage(text, true);

    try {
      final result = await _chatSession.encryptText(body: text);
      _logLine('Verschlüsselt: ${result.frame.length} bytes');
      await _transport.sendMessage(result.frame);
      _logLine('Gesendet!');
    } catch (e) {
      _logLine('Senden fehlgeschlagen: $e');
    }
  }

  Future<void> _startAdvertising() async {
    _setRole(ChatRole.responder); // We are the peripheral, waiting for connection

    try {
      final advertiseData = AdvertiseData(
        serviceUuid: kChatServiceUuid,
        includeDeviceName: false,
      );
      final advertiseSettings = AdvertiseSettings(
        advertiseMode: AdvertiseMode.advertiseModeBalanced,
        txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
        connectable: true,
        timeout: 0,
      );
      await _peripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: advertiseSettings,
      );
      setState(() {
        _isAdvertising = true;
      });
      _logLine('Advertising gestartet (Responder-Rolle)');
    } catch (error) {
      _logLine('Advertising Fehler: $error');
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await _peripheral.stop();
      setState(() {
        _isAdvertising = false;
      });
      _logLine('Advertising gestoppt.');
    } catch (error) {
      _logLine('Advertising Stop Fehler: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectedDevice != null && _writeChar != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('BLE Chat${_isInitiator ? " (Initiator)" : " (Responder)"}'),
        actions: [
          if (isConnected)
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isConnected ? Colors.green.shade100 : Colors.orange.shade100,
            child: Row(
              children: [
                Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isConnected
                        ? 'Verbunden mit ${_connectedDevice!.remoteId}'
                        : 'Nicht verbunden',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (!isConnected) ...[
                  TextButton(
                    onPressed: _requestPermissions,
                    child: const Text('Permissions'),
                  ),
                ],
              ],
            ),
          ),

          // Main content
          Expanded(
            child: isConnected ? _buildChatView() : _buildConnectionView(),
          ),

          // Log section (collapsible)
          ExpansionTile(
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
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Advertising section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Peripheral (warten auf Verbindung)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
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
                          Text('Warte...'),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hinweis: flutter_ble_peripheral kann nur Advertising. '
                  'Für echte GATT-Characteristics brauchen wir ein natives Plugin.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Scan section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Central (verbinden zu Peer)',
                    style: Theme.of(context).textTheme.titleMedium),
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
                const SizedBox(height: 12),
                if (_scanResults.isEmpty)
                  const Text('Keine Geräte gefunden.',
                      style: TextStyle(color: Colors.grey))
                else
                  ..._scanResults.map((result) => ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(result.device.platformName.isNotEmpty
                            ? result.device.platformName
                            : result.device.remoteId.toString()),
                        subtitle: Text('RSSI: ${result.rssi}'),
                        trailing: ElevatedButton(
                          onPressed: () => _connectToDevice(result.device),
                          child: const Text('Connect'),
                        ),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatView() {
    return Column(
      children: [
        // Messages list
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
                    return Align(
                      alignment:
                          msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: msg.isMe
                              ? Colors.teal.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        child: Text(msg.text),
                      ),
                    );
                  },
                ),
        ),

        // Input field
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
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
}

class _ChatBubble {
  _ChatBubble({required this.text, required this.isMe});

  final String text;
  final bool isMe;
}

/// Transport link that uses a callback to send bytes
class _BleTransportLink implements TransportLink {
  _BleTransportLink({required this.sendCallback});

  final void Function(Uint8List bytes) sendCallback;

  @override
  void send(String from, Uint8List bytes) {
    sendCallback(bytes);
  }
}
