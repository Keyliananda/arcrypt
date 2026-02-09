/// GATT Client for PRSM Chat (Central Role)
///
/// This implements the Central side of the BLE transport:
/// - Scans for and connects to Peripherals hosting the Chat service
/// - Writes data to RX characteristic (send to Peripheral)
/// - Receives notifications from TX characteristic (receive from Peripheral)
/// - Integrates with Transport layer for reliable delivery

import 'dart:async';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

import 'ble_constants.dart';
import '../transport/transport.dart';

/// Discovered peripheral info
class DiscoveredPeripheral {
  DiscoveredPeripheral({
    required this.peripheral,
    required this.rssi,
    required this.name,
  });

  final Peripheral peripheral;
  final int rssi;
  final String? name;

  @override
  String toString() => 'DiscoveredPeripheral(name: $name, rssi: $rssi)';
}

/// GATT Client that connects to PRSM Chat Peripherals
class GattClient implements TransportLink {
  GattClient({void Function(String)? logger}) : _logger = logger;

  final void Function(String)? _logger;
  final CentralManager _central = CentralManager();

  // Connected peripheral
  Peripheral? _connectedPeripheral;

  // Discovered characteristics
  GATTCharacteristic? _rxCharacteristic;
  GATTCharacteristic? _txCharacteristic;

  // State
  bool _isInitialized = false;
  bool _isScanning = false;
  bool _isConnected = false;

  // Streams
  final StreamController<Uint8List> _inboundController =
      StreamController.broadcast();
  final StreamController<DiscoveredPeripheral> _discoveredController =
      StreamController.broadcast();
  final StreamController<bool> _connectionController =
      StreamController.broadcast();

  /// Stream of inbound data from Peripheral
  Stream<Uint8List> get inbound => _inboundController.stream;

  /// Stream of discovered peripherals during scan
  Stream<DiscoveredPeripheral> get discovered => _discoveredController.stream;

  /// Stream of connection state changes
  Stream<bool> get connectionState => _connectionController.stream;

  /// Whether we're scanning
  bool get isScanning => _isScanning;

  /// Whether we're connected
  bool get isConnected => _isConnected;

  /// The connected peripheral
  Peripheral? get connectedPeripheral => _connectedPeripheral;

  // Subscriptions
  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;
  StreamSubscription<DiscoveredEventArgs>? _discoverySub;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>? _connectionSub;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _notifySub;

  /// Initialize the Central manager
  Future<void> initialize() async {
    if (_isInitialized) {
      _log('Already initialized');
      return;
    }

    _log('Initializing GATT Client...');

    // Check BLE state
    final state = _central.state;
    if (state != BluetoothLowEnergyState.poweredOn) {
      _log('Bluetooth not powered on: $state');
      throw Exception('Bluetooth is not powered on');
    }

    // Listen for state changes
    _stateSub = _central.stateChanged.listen((event) {
      _log('BLE State changed: ${event.state}');
      if (event.state != BluetoothLowEnergyState.poweredOn) {
        _handleBleDisabled();
      }
    });

    // Listen for connection state changes
    _connectionSub = _central.connectionStateChanged.listen((event) {
      _log('Connection state changed: ${event.state}');
      if (event.state == ConnectionState.disconnected && _isConnected) {
        // Disconnected
        _handleDisconnect();
      }
    });

    // Listen for characteristic notifications
    _notifySub = _central.characteristicNotified.listen((event) {
      if (event.characteristic.uuid == kTxCharacteristicUuid) {
        _handleNotification(event);
      }
    });

    _isInitialized = true;
    _log('GATT Client initialized');
  }

  /// Start scanning for Peripherals with our service
  Future<void> startScan() async {
    if (!_isInitialized) {
      throw StateError('Client not initialized');
    }
    if (_isScanning) {
      _log('Already scanning');
      return;
    }

    _log('Starting scan...');

    // Set up discovery listener
    _discoverySub = _central.discovered.listen((event) {
      // Check if this peripheral advertises our service
      final hasService = event.advertisement.serviceUUIDs.any(
        (uuid) => uuid == kChatServiceUuid,
      );

      if (hasService) {
        final discovered = DiscoveredPeripheral(
          peripheral: event.peripheral,
          rssi: event.rssi,
          name: event.advertisement.name,
        );
        _log(
          'Discovered: ${discovered.name ?? event.peripheral.uuid} (RSSI: ${discovered.rssi})',
        );
        _discoveredController.add(discovered);
      }
    });

    // Start scanning with service filter
    await _central.startDiscovery(serviceUUIDs: [kChatServiceUuid]);

    _isScanning = true;
    _log('Scan started');
  }

  /// Stop scanning
  Future<void> stopScan() async {
    if (!_isScanning) return;

    await _central.stopDiscovery();
    await _discoverySub?.cancel();
    _discoverySub = null;

    _isScanning = false;
    _log('Scan stopped');
  }

  /// Connect to a discovered Peripheral
  Future<void> connect(Peripheral peripheral) async {
    if (!_isInitialized) {
      throw StateError('Client not initialized');
    }
    if (_isConnected) {
      throw StateError('Already connected');
    }

    _log('Connecting to ${peripheral.uuid}...');

    // Stop scanning if we're scanning
    if (_isScanning) {
      await stopScan();
    }

    try {
      // Connect
      await _central.connect(peripheral);
      _connectedPeripheral = peripheral;
      _isConnected = true;
      _log('Connected');

      // Discover services
      _log('Discovering services...');
      final services = await _central.discoverGATT(peripheral);
      _log('Found ${services.length} services');

      // Find our service
      GATTService? chatService;
      for (final service in services) {
        if (service.uuid == kChatServiceUuid) {
          chatService = service;
          break;
        }
      }

      if (chatService == null) {
        _log('Chat service not found!');
        await disconnect();
        throw Exception('Chat service not found on peripheral');
      }

      _log('Found chat service');

      // Find characteristics
      for (final char in chatService.characteristics) {
        if (char.uuid == kRxCharacteristicUuid) {
          _rxCharacteristic = char;
          _log('Found RX characteristic');
        } else if (char.uuid == kTxCharacteristicUuid) {
          _txCharacteristic = char;
          _log('Found TX characteristic');
        }
      }

      if (_rxCharacteristic == null || _txCharacteristic == null) {
        _log('Required characteristics not found');
        await disconnect();
        throw Exception('Required characteristics not found');
      }

      // Subscribe to TX notifications
      _log('Subscribing to TX notifications...');
      await _central.setCharacteristicNotifyState(
        peripheral,
        _txCharacteristic!,
        state: true,
      );
      _log('Subscribed to notifications');

      _connectionController.add(true);
      _log('Connection complete, ready for data transfer');
    } catch (e) {
      _log('Connection failed: $e');
      _handleDisconnect();
      rethrow;
    }
  }

  /// Handle incoming notifications from TX characteristic
  void _handleNotification(GATTCharacteristicNotifiedEventArgs event) {
    final bytes = Uint8List.fromList(event.value);
    _log('RX: ${bytes.length} bytes from Peripheral');
    _inboundController.add(bytes);
  }

  /// Send data to the connected Peripheral via RX write
  @override
  Future<void> send(Uint8List bytes) async {
    if (!_isConnected ||
        _connectedPeripheral == null ||
        _rxCharacteristic == null) {
      throw StateError('cannot send: not connected');
    }

    _log('TX: ${bytes.length} bytes to Peripheral');

    // Write to RX characteristic
    await _central.writeCharacteristic(
      _connectedPeripheral!,
      _rxCharacteristic!,
      value: bytes,
      type: GATTCharacteristicWriteType.withResponse,
    );
  }

  /// Disconnect from the current Peripheral
  Future<void> disconnect() async {
    if (!_isConnected || _connectedPeripheral == null) return;

    _log('Disconnecting...');

    try {
      // Unsubscribe from notifications
      if (_txCharacteristic != null) {
        await _central.setCharacteristicNotifyState(
          _connectedPeripheral!,
          _txCharacteristic!,
          state: false,
        );
      }

      await _central.disconnect(_connectedPeripheral!);
    } catch (e) {
      _log('Disconnect error: $e');
    }

    _handleDisconnect();
  }

  /// Handle disconnection
  void _handleDisconnect() {
    _connectedPeripheral = null;
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _isConnected = false;
    _connectionController.add(false);
    _log('Disconnected');
  }

  /// Handle BLE being disabled
  void _handleBleDisabled() {
    _log('BLE disabled, cleaning up...');
    _isScanning = false;
    _handleDisconnect();
  }

  void _log(String message) {
    _logger?.call('[GattClient] $message');
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stopScan();
    await disconnect();

    await _stateSub?.cancel();
    await _connectionSub?.cancel();
    await _notifySub?.cancel();

    await _inboundController.close();
    await _discoveredController.close();
    await _connectionController.close();
  }
}
