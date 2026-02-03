/// BLE module exports
/// 
/// This module provides the BLE transport layer for PRSM Chat:
/// - GattServer: Peripheral role (hosts GATT service, receives connections)
/// - GattClient: Central role (scans and connects to Peripherals)
/// - Constants: UUIDs and configuration from Transport-Spec

export 'ble_constants.dart';
export 'gatt_server.dart';
export 'gatt_client.dart';

// Re-export commonly used types from bluetooth_low_energy
export 'package:bluetooth_low_energy/bluetooth_low_energy.dart' show
  BluetoothLowEnergyState,
  Peripheral,
  Central;
