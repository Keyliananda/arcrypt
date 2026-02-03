/// GATT Server for PRSM Chat (Peripheral Role)
/// 
/// This implements the Peripheral side of the BLE transport:
/// - Hosts the Chat GATT Service with RX and TX characteristics
/// - Receives writes from Central on RX characteristic
/// - Sends notifications to Central via TX characteristic
/// - Integrates with Transport layer for reliable delivery

import 'dart:async';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

import 'ble_constants.dart';
import '../transport/transport.dart';

/// GATT Server that hosts the PRSM Chat service
class GattServer implements TransportLink {
  GattServer({
    void Function(String)? logger,
  }) : _logger = logger;

  final void Function(String)? _logger;
  final PeripheralManager _peripheral = PeripheralManager();
  
  // Connected centrals (we track the first one for MVP)
  Central? _connectedCentral;
  
  // Characteristics (stored after adding service)
  GATTCharacteristic? _rxCharacteristic;
  GATTCharacteristic? _txCharacteristic;
  
  // State
  bool _isRunning = false;
  bool _isAdvertising = false;
  
  // Streams
  final StreamController<Uint8List> _inboundController = StreamController.broadcast();
  final StreamController<bool> _connectionController = StreamController.broadcast();
  
  /// Stream of inbound data from Central
  Stream<Uint8List> get inbound => _inboundController.stream;
  
  /// Stream of connection state changes
  Stream<bool> get connectionState => _connectionController.stream;
  
  /// Whether the server is running
  bool get isRunning => _isRunning;
  
  /// Whether we're advertising
  bool get isAdvertising => _isAdvertising;
  
  /// Whether a Central is connected
  bool get isConnected => _connectedCentral != null;

  // Subscriptions
  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;
  StreamSubscription<CentralConnectionStateChangedEventArgs>? _connectionSub;
  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>? _writeSub;
  StreamSubscription<GATTCharacteristicNotifyStateChangedEventArgs>? _notifyStateSub;

  /// Initialize the GATT server and add the service
  Future<void> start() async {
    if (_isRunning) {
      _log('Server already running');
      return;
    }

    _log('Starting GATT Server...');

    // Listen for state changes first
    _stateSub = _peripheral.stateChanged.listen((event) {
      _log('BLE State changed: ${event.state}');
      if (event.state == BluetoothLowEnergyState.poweredOn && !_isRunning) {
        // BLE just became available, try to setup service
        _trySetupService();
      } else if (event.state != BluetoothLowEnergyState.poweredOn) {
        _handleBleDisabled();
      }
    });

    // Listen for connection state changes (Android only, but we set it up anyway)
    try {
      _connectionSub = _peripheral.connectionStateChanged.listen((event) {
        _log('Connection state changed: ${event.state}');
        if (event.state == ConnectionState.connected) {
          // Connected
          _connectedCentral = event.central;
          _connectionController.add(true);
          _log('Central connected: ${event.central.uuid}');
        } else {
          // Disconnected
          _connectedCentral = null;
          _connectionController.add(false);
          _log('Central disconnected');
        }
      });
    } catch (e) {
      _log('Connection state events not supported: $e');
    }

    // Check BLE state and setup if ready
    final state = _peripheral.state;
    _log('Current BLE state: $state');
    
    if (state == BluetoothLowEnergyState.poweredOn) {
      await _trySetupService();
    } else {
      _log('Waiting for Bluetooth to be powered on...');
      // Don't throw - just wait for state change
    }
  }

  Future<void> _trySetupService() async {
    if (_isRunning) return;
    
    try {
      // Create the GATT service
      await _setupGattService();
      _isRunning = true;
      _log('GATT Server started');
    } catch (e) {
      _log('Failed to setup GATT service: $e');
    }
  }

  /// Set up the GATT service with characteristics
  Future<void> _setupGattService() async {
    _log('Setting up GATT service...');

    // Define RX characteristic (Central writes to us)
    _rxCharacteristic = GATTCharacteristic.mutable(
      uuid: kRxCharacteristicUuid,
      properties: [
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
      ],
      permissions: [
        GATTCharacteristicPermission.write,
      ],
      descriptors: [],
    );

    // Define TX characteristic (we notify Central)
    _txCharacteristic = GATTCharacteristic.mutable(
      uuid: kTxCharacteristicUuid,
      properties: [
        GATTCharacteristicProperty.notify,
        GATTCharacteristicProperty.read,
      ],
      permissions: [
        GATTCharacteristicPermission.read,
      ],
      descriptors: [],
    );

    // Create the service
    final service = GATTService(
      uuid: kChatServiceUuid,
      isPrimary: true,
      includedServices: [],
      characteristics: [
        _rxCharacteristic!,
        _txCharacteristic!,
      ],
    );

    // Remove any existing services first
    await _peripheral.removeAllServices();

    // Add our service
    await _peripheral.addService(service);
    _log('GATT service added');

    // Listen for write requests on RX characteristic
    _writeSub = _peripheral.characteristicWriteRequested.listen((event) {
      if (event.characteristic.uuid == kRxCharacteristicUuid) {
        _handleWriteRequest(event);
      }
    });

    // Listen for notify state changes on TX characteristic
    _notifyStateSub = _peripheral.characteristicNotifyStateChanged.listen((event) {
      if (event.characteristic.uuid == kTxCharacteristicUuid) {
        _log('TX notify state changed: ${event.state}');
        // On iOS, we detect connection via notify subscription
        if (event.state) {
          _connectedCentral = event.central;
          _connectionController.add(true);
          _log('Central subscribed (iOS connection detected)');
        }
      }
    });

    _log('GATT service setup complete');
  }

  /// Handle incoming write requests from Central
  void _handleWriteRequest(GATTCharacteristicWriteRequestedEventArgs event) {
    final bytes = Uint8List.fromList(event.request.value);
    _log('RX: ${bytes.length} bytes from Central');
    
    // Respond to the write request
    _peripheral.respondWriteRequest(event.request);

    // Track connected central if not already tracked
    if (_connectedCentral == null) {
      _connectedCentral = event.central;
      _connectionController.add(true);
      _log('Central detected via write');
    }

    // Forward to inbound stream
    _inboundController.add(bytes);
  }

  /// Start advertising the service
  Future<void> startAdvertising({String? name}) async {
    // If server not running, try to start it first
    if (!_isRunning) {
      _log('Server not running, attempting to start...');
      final state = _peripheral.state;
      if (state == BluetoothLowEnergyState.poweredOn) {
        await _trySetupService();
      }
      
      // If still not running, throw
      if (!_isRunning) {
        throw StateError('Server not started - is Bluetooth enabled?');
      }
    }
    
    if (_isAdvertising) {
      _log('Already advertising');
      return;
    }

    _log('Starting advertising...');

    final advertisement = Advertisement(
      name: name,
      serviceUUIDs: [kChatServiceUuid],
    );

    await _peripheral.startAdvertising(advertisement);
    _isAdvertising = true;
    _log('Advertising started');
  }

  /// Stop advertising
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    await _peripheral.stopAdvertising();
    _isAdvertising = false;
    _log('Advertising stopped');
  }

  /// Send data to the connected Central via TX notification
  @override
  void send(String from, Uint8List bytes) {
    if (_txCharacteristic == null || _connectedCentral == null) {
      _log('TX: cannot send - no connected central or characteristic');
      return;
    }

    _log('TX: ${bytes.length} bytes to Central');

    // Notify the connected central
    _peripheral.notifyCharacteristic(
      _connectedCentral!,
      _txCharacteristic!,
      value: bytes,
    );
  }

  /// Handle BLE being disabled
  void _handleBleDisabled() {
    _log('BLE disabled, cleaning up...');
    _isAdvertising = false;
    _connectedCentral = null;
    _connectionController.add(false);
  }

  /// Stop the server and clean up
  Future<void> stop() async {
    if (!_isRunning) return;

    _log('Stopping GATT Server...');

    await stopAdvertising();
    
    await _stateSub?.cancel();
    await _connectionSub?.cancel();
    await _writeSub?.cancel();
    await _notifyStateSub?.cancel();

    await _peripheral.removeAllServices();

    _isRunning = false;
    _connectedCentral = null;
    _log('GATT Server stopped');
  }

  void _log(String message) {
    _logger?.call('[GattServer] $message');
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _inboundController.close();
    await _connectionController.close();
  }
}
