import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'transport/relay_config_store.dart';
import 'transport/relay_runtime_config.dart';

class RelayConfigScreen extends StatefulWidget {
  const RelayConfigScreen({super.key, required this.environmentConfig});

  final RelayRuntimeConfig environmentConfig;

  @override
  State<RelayConfigScreen> createState() => _RelayConfigScreenState();
}

class _RelayConfigScreenState extends State<RelayConfigScreen> {
  final RelayConfigStore _store = const RelayConfigStore();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _inboundController = TextEditingController();
  final TextEditingController _outboundController = TextEditingController();
  final TextEditingController _wakeSecretController = TextEditingController();
  final TextEditingController _peerWakeTokenController =
      TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _hasStoredConfig = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _inboundController.dispose();
    _outboundController.dispose();
    _wakeSecretController.dispose();
    _peerWakeTokenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final stored = await _store.load();
    final source = stored ?? widget.environmentConfig;

    _baseUrlController.text = source.baseUrl;
    _inboundController.text = source.inboundMailboxId;
    _outboundController.text = source.outboundMailboxId;
    _wakeSecretController.text = source.wakeHmacSecret;
    _peerWakeTokenController.text = source.peerWakeToken;

    if (!mounted) return;
    setState(() {
      _loading = false;
      _hasStoredConfig = stored != null && stored.hasAnyValue;
    });
  }

  RelayRuntimeConfig _buildConfigFromForm() {
    return RelayRuntimeConfig(
      baseUrl: _baseUrlController.text.trim(),
      inboundMailboxId: _inboundController.text.trim(),
      outboundMailboxId: _outboundController.text.trim(),
      wakeHmacSecret: _wakeSecretController.text.trim(),
      peerWakeToken: _peerWakeTokenController.text.trim(),
    );
  }

  Future<void> _save() async {
    final config = _buildConfigFromForm();
    if (!config.isRemoteAvailable) {
      setState(() {
        _statusIsError = true;
        _status = config.remoteStatusLabel;
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    await _store.save(config);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _hasStoredConfig = true;
      _statusIsError = false;
      _status = 'Gespeichert. Runtime-Konfig wird ab sofort bevorzugt.';
    });
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    await _store.clear();
    if (!mounted) return;

    _baseUrlController.text = widget.environmentConfig.baseUrl;
    _inboundController.text = widget.environmentConfig.inboundMailboxId;
    _outboundController.text = widget.environmentConfig.outboundMailboxId;
    _wakeSecretController.text = widget.environmentConfig.wakeHmacSecret;
    _peerWakeTokenController.text = widget.environmentConfig.peerWakeToken;

    setState(() {
      _busy = false;
      _hasStoredConfig = false;
      _statusIsError = false;
      _status = 'Gespeicherte Runtime-Konfig gelöscht.';
    });
  }

  Future<void> _testConnection() async {
    final config = _buildConfigFromForm();
    final baseUri = config.baseUri;
    if (baseUri == null) {
      setState(() {
        _statusIsError = true;
        _status = 'Relay URL ungültig.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final healthUri = baseUri.replace(path: '/v1/health');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final request = await client.postUrl(healthUri);
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.write(jsonEncode(<String, String>{}));
        final response = await request.close();
        final ok = response.statusCode >= 200 && response.statusCode < 300;
        if (!mounted) return;
        setState(() {
          _busy = false;
          _statusIsError = !ok;
          _status = ok
              ? 'Relay erreichbar (HTTP ${response.statusCode}).'
              : 'Relay antwortet, aber mit HTTP ${response.statusCode}.';
        });
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusIsError = true;
        _status = 'Relay-Test fehlgeschlagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Relay konfigurieren')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _hasStoredConfig
                ? 'Aktiv: gespeicherte Runtime-Konfig'
                : 'Aktiv: Build-Defines (Fallback)',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Relay Base URL',
              hintText: 'https://relay.example',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _inboundController,
            decoration: const InputDecoration(labelText: 'Inbound Mailbox ID'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _outboundController,
            decoration: const InputDecoration(labelText: 'Outbound Mailbox ID'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _wakeSecretController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Wake HMAC Secret (optional)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _peerWakeTokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Peer Wake Token (optional)',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Speichern'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _testConnection,
                icon: const Icon(Icons.health_and_safety),
                label: const Text('Verbindung testen'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Gespeicherte löschen'),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
          if (_status != null) ...[
            const SizedBox(height: 14),
            Text(
              _status!,
              style: TextStyle(
                color: _statusIsError
                    ? Colors.red.shade700
                    : Colors.green.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
