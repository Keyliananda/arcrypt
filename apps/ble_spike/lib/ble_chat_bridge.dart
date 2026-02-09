import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'transport/transport.dart';

/// UUIDs for our custom GATT service
const String kChatServiceUuid = 'F00D0001-1212-EFDE-1523-785FEABCD123';
const String kChatWriteCharUuid = 'F00D0002-1212-EFDE-1523-785FEABCD123';
const String kChatNotifyCharUuid = 'F00D0003-1212-EFDE-1523-785FEABCD123';

/// A BLE transport link that uses GATT characteristics.
///
/// This bridge:
/// - Connects to a remote device's GATT service
/// - Writes outbound packets to the write characteristic
/// - Receives inbound packets via notifications on the notify characteristic
class BleChatBridge implements TransportLink {
  BleChatBridge({required this.device, void Function(String)? logger})
    : _logger = logger;

  final BluetoothDevice device;
  final void Function(String)? _logger;

  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;

  final StreamController<Uint8List> _inbound = StreamController.broadcast();
  Stream<Uint8List> get inbound => _inbound.stream;

  bool _connected = false;
  bool get isConnected => _connected;

  Future<void> connect() async {
    _log('Connecting to ${device.remoteId}...');

    await device.connect(timeout: const Duration(seconds: 15));
    _connected = true;
    _log('Connected, discovering services...');

    final services = await device.discoverServices();
    _log('Found ${services.length} services');

    BluetoothService? chatService;
    for (final service in services) {
      if (service.uuid.toString().toUpperCase() ==
          kChatServiceUuid.toUpperCase()) {
        chatService = service;
        break;
      }
    }

    if (chatService == null) {
      // Try to find by partial match (some platforms change UUID format)
      for (final service in services) {
        final uuidStr = service.uuid.toString().toUpperCase();
        if (uuidStr.contains('F00D0001')) {
          chatService = service;
          break;
        }
      }
    }

    if (chatService == null) {
      _log('Chat service not found! Available services:');
      for (final s in services) {
        _log('  - ${s.uuid}');
      }
      throw Exception('Chat GATT service not found');
    }

    _log('Found chat service: ${chatService.uuid}');

    for (final char in chatService.characteristics) {
      final charUuid = char.uuid.toString().toUpperCase();
      if (charUuid.contains('F00D0002')) {
        _writeChar = char;
        _log('Found write characteristic');
      } else if (charUuid.contains('F00D0003')) {
        _notifyChar = char;
        _log('Found notify characteristic');
      }
    }

    if (_notifyChar != null) {
      await _notifyChar!.setNotifyValue(true);
      _notifySub = _notifyChar!.onValueReceived.listen((value) {
        final bytes = Uint8List.fromList(value);
        _log('Received ${bytes.length} bytes via notify');
        _inbound.add(bytes);
      });
      _log('Subscribed to notifications');
    }

    _log('Bridge ready');
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    try {
      await device.disconnect();
    } catch (_) {}
    _connected = false;
    _log('Disconnected');
  }

  @override
  Future<void> send(Uint8List bytes) async {
    if (_writeChar == null) {
      throw StateError('cannot send: write characteristic not available');
    }
    _log('Sending ${bytes.length} bytes');
    // Use writeWithoutResponse for lower latency if supported
    await _writeChar!.write(bytes.toList(), withoutResponse: false);
  }

  void _log(String message) {
    _logger?.call('[BleBridge] $message');
  }
}

/// Simplified bridge for testing without full GATT service.
/// Uses a shared in-memory channel for local testing.
class LocalTestBridge implements TransportLink {
  LocalTestBridge({required this.name, required this.peer});

  final String name;
  LocalTestBridge? peer;

  final StreamController<Uint8List> _inbound = StreamController.broadcast();
  Stream<Uint8List> get inbound => _inbound.stream;

  void receive(Uint8List bytes) {
    _inbound.add(bytes);
  }

  @override
  Future<void> send(Uint8List bytes) async {
    // Simulate sending to peer
    peer?.receive(Uint8List.fromList(bytes));
  }
}
