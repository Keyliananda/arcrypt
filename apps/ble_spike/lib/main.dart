import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const BleSpikeApp());
}

class BleSpikeApp extends StatelessWidget {
  const BleSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Spike',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const BleSpikeHome(),
    );
  }
}

class BleSpikeHome extends StatefulWidget {
  const BleSpikeHome({super.key});

  @override
  State<BleSpikeHome> createState() => _BleSpikeHomeState();
}

class _BleSpikeHomeState extends State<BleSpikeHome> {
  static const _defaultServiceUuid = 'F00D0001-1212-EFDE-1523-785FEABCD123';

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final TextEditingController _serviceUuidController =
      TextEditingController(text: _defaultServiceUuid);

  final List<String> _log = <String>[];
  List<ScanResult> _scanResults = <ScanResult>[];
  bool _isScanning = false;
  bool _isAdvertising = false;

  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanningSub;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _scanResultsSub?.cancel();
    _isScanningSub?.cancel();
    _serviceUuidController.dispose();
    super.dispose();
  }

  void _logLine(String message) {
    final stamp = DateTime.now().toIso8601String();
    setState(() {
      _log.insert(0, '$stamp  $message');
      if (_log.length > 80) {
        _log.removeRange(80, _log.length);
      }
    });
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) {
      _logLine('Permissions: iOS verwaltet Bluetooth-Prompts automatisch.');
      return;
    }

    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();

    _logLine(
      'Permissions: ${statuses.entries.map((entry) => '${entry.key}:${entry.value}').join(', ')}',
    );
  }

  Future<void> _startScan() async {
    final serviceUuid = _serviceUuidController.text.trim();
    setState(() {
      _scanResults = <ScanResult>[];
    });
    _logLine('Scan gestartet (30s) - Filter: $serviceUuid');
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 30),
      withServices: serviceUuid.isNotEmpty
          ? [Guid(serviceUuid)]
          : [],
    );
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    _logLine('Scan gestoppt.');
  }

  Future<void> _connect(ScanResult result) async {
    try {
      await result.device.connect(timeout: const Duration(seconds: 10));
      _logLine('Connect OK: ${result.device}');
    } catch (error) {
      _logLine('Connect Fehler: $error');
    }
  }

  Future<void> _disconnect(ScanResult result) async {
    try {
      await result.device.disconnect();
      _logLine('Disconnect OK: ${result.device}');
    } catch (error) {
      _logLine('Disconnect Fehler: $error');
    }
  }

  Future<void> _startAdvertising() async {
    final serviceUuid = _serviceUuidController.text.trim();
    if (serviceUuid.isEmpty) {
      _logLine('Service UUID fehlt.');
      return;
    }

    try {
      final advertiseData = AdvertiseData(
        serviceUuid: serviceUuid,
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
      _logLine('Advertising gestartet: $serviceUuid');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Spike'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Permissions',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Android: Scan/Connect/Advertise + Location erforderlich (ab Android 12 BLE-Permissions).',
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _requestPermissions,
                  child: const Text('Berechtigungen anfordern'),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Central (Scan)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _isScanning ? null : _startScan,
                      child: const Text('Scan starten'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _isScanning ? _stopScan : null,
                      child: const Text('Stop'),
                    ),
                    const SizedBox(width: 12),
                    Text(_isScanning ? 'läuft…' : 'idle'),
                  ],
                ),
                const SizedBox(height: 12),
                if (_scanResults.isEmpty)
                  const Text('Keine Ergebnisse.')
                else
                  Column(
                    children: _scanResults.map((result) {
                      return Card(
                        child: ListTile(
                          title: Text(result.device.toString()),
                          subtitle: Text('RSSI: ${result.rssi}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _connect(result),
                                child: const Text('Connect'),
                              ),
                              TextButton(
                                onPressed: () => _disconnect(result),
                                child: const Text('Disconnect'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          _Section(
            title: 'Peripheral (Advertising)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _serviceUuidController,
                  decoration: const InputDecoration(
                    labelText: 'Service UUID',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _isAdvertising ? null : _startAdvertising,
                      child: const Text('Advertise starten'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _isAdvertising ? _stopAdvertising : null,
                      child: const Text('Stop'),
                    ),
                    const SizedBox(width: 12),
                    Text(_isAdvertising ? 'läuft…' : 'idle'),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hinweis: flutter_ble_peripheral kann nur Advertising, kein Custom GATT-Service.',
                ),
              ],
            ),
          ),
          _Section(
            title: 'Log',
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _log.isEmpty
                  ? const Text('Noch keine Einträge.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _log
                          .map((line) => Text(
                                line,
                                style: const TextStyle(fontSize: 12),
                              ))
                          .toList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
