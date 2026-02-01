import 'dart:async';
import 'dart:typed_data';

const int kProtocolVersion = 1;
const int kTypeData = 1;
const int kTypeAck = 2;

const int kFlagStart = 1 << 0;
const int kFlagEnd = 1 << 1;

class TransportConfig {
  const TransportConfig({
    this.maxPayload = 176,
    this.maxMessageBytes = 64 * 1024,
    this.ackTimeout = const Duration(milliseconds: 250),
    this.maxRetries = 5,
  });

  final int maxPayload;
  final int maxMessageBytes;
  final Duration ackTimeout;
  final int maxRetries;
}

class TransportPacket {
  TransportPacket({
    required this.version,
    required this.type,
    required this.flags,
    required this.seq,
    required this.payload,
  });

  final int version;
  final int type;
  final int flags;
  final int seq;
  final Uint8List payload;

  Uint8List encode() {
    final bytes = Uint8List(4 + payload.length);
    bytes[0] = version;
    bytes[1] = type;
    bytes[2] = flags;
    bytes[3] = seq;
    if (payload.isNotEmpty) {
      bytes.setRange(4, bytes.length, payload);
    }
    return bytes;
  }

  static TransportPacket decode(Uint8List bytes) {
    if (bytes.length < 4) {
      throw const FormatException('packet too short');
    }
    return TransportPacket(
      version: bytes[0],
      type: bytes[1],
      flags: bytes[2],
      seq: bytes[3],
      payload: Uint8List.fromList(bytes.sublist(4)),
    );
  }
}

abstract class TransportLink {
  void send(String from, Uint8List bytes);
}

class TransportStats {
  int packetsSent = 0;
  int packetsReceived = 0;
  int dataPacketsSent = 0;
  int dataPacketsReceived = 0;
  int ackPacketsSent = 0;
  int ackPacketsReceived = 0;
  int retransmissions = 0;
  int duplicatePackets = 0;
  int protocolErrors = 0;
  int ackTimeouts = 0;
  int messagesDelivered = 0;
  int bytesDelivered = 0;
}

class TransportException implements Exception {
  TransportException(this.message);

  final String message;

  @override
  String toString() => 'TransportException: $message';
}

class TransportEndpoint {
  TransportEndpoint({
    required this.name,
    required this.link,
    this.config = const TransportConfig(),
    void Function(String message)? logger,
  }) : _logger = logger;

  final String name;
  final TransportLink link;
  final TransportConfig config;
  final void Function(String message)? _logger;

  final TransportStats _stats = TransportStats();
  TransportStats get stats => _stats;

  final StreamController<Uint8List> _messages = StreamController.broadcast();
  Stream<Uint8List> get messages => _messages.stream;

  int _sendSeq = 0;
  int _recvSeqExpected = 0;

  BytesBuilder? _receiveBuffer;
  bool _receiving = false;

  _InFlight? _inFlight;
  Future<void> _sendChain = Future<void>.value();

  Future<void> sendMessage(Uint8List data) {
    _sendChain = _sendChain
        .catchError((_) {})
        .then((_) => _sendMessageInternal(data));
    return _sendChain;
  }

  void handlePacket(Uint8List bytes) {
    _stats.packetsReceived++;
    TransportPacket packet;
    try {
      packet = TransportPacket.decode(bytes);
    } on FormatException catch (_) {
      _stats.protocolErrors++;
      _log('packet decode failed');
      return;
    }

    if (packet.version != kProtocolVersion) {
      _stats.protocolErrors++;
      _log('version mismatch: ${packet.version}');
      return;
    }

    if (packet.type == kTypeData) {
      _handleData(packet);
    } else if (packet.type == kTypeAck) {
      _handleAck(packet.seq);
    } else {
      _stats.protocolErrors++;
      _log('unknown packet type: ${packet.type}');
    }
  }

  void resetSession() {
    _sendSeq = 0;
    _recvSeqExpected = 0;
    _receiveBuffer = null;
    _receiving = false;
    _inFlight = null;
  }

  Future<void> _sendMessageInternal(Uint8List data) async {
    if (data.length > config.maxMessageBytes) {
      throw TransportException('message exceeds maxMessageBytes');
    }

    if (data.isEmpty) {
      await _sendChunk(Uint8List(0), isFirst: true, isLast: true);
      return;
    }

    var offset = 0;
    var chunkIndex = 0;
    while (offset < data.length) {
      var end = offset + config.maxPayload;
      if (end > data.length) {
        end = data.length;
      }
      final chunk = Uint8List.fromList(data.sublist(offset, end));
      final isFirst = chunkIndex == 0;
      final isLast = end >= data.length;
      await _sendChunk(chunk, isFirst: isFirst, isLast: isLast);
      offset = end;
      chunkIndex++;
    }
  }

  Future<void> _sendChunk(
    Uint8List chunk, {
    required bool isFirst,
    required bool isLast,
  }) async {
    var flags = 0;
    if (isFirst) {
      flags |= kFlagStart;
    }
    if (isLast) {
      flags |= kFlagEnd;
    }

    final packet = TransportPacket(
      version: kProtocolVersion,
      type: kTypeData,
      flags: flags,
      seq: _sendSeq,
      payload: chunk,
    );

    await _sendPacketWithAck(packet);
  }

  Future<void> _sendPacketWithAck(TransportPacket packet) async {
    if (_inFlight != null) {
      throw StateError('send already in flight');
    }
    final completer = Completer<void>();
    _inFlight = _InFlight(seq: packet.seq, completer: completer);

    var attempts = 0;
    while (true) {
      attempts++;
      _sendPacket(packet);
      final acked = await _waitForAck(completer.future, config.ackTimeout);
      if (acked) {
        return;
      }
      _stats.ackTimeouts++;
      if (attempts >= config.maxRetries) {
        _inFlight = null;
        throw TransportException('ack timeout after $attempts attempts');
      }
      _stats.retransmissions++;
    }
  }

  Future<bool> _waitForAck(Future<void> ackFuture, Duration timeout) async {
    final result = await Future.any(<Future<bool>>[
      ackFuture.then((_) => true),
      Future<bool>.delayed(timeout, () => false),
    ]);
    return result;
  }

  void _sendPacket(TransportPacket packet) {
    _stats.packetsSent++;
    if (packet.type == kTypeData) {
      _stats.dataPacketsSent++;
    } else if (packet.type == kTypeAck) {
      _stats.ackPacketsSent++;
    }
    link.send(name, packet.encode());
  }

  void _handleData(TransportPacket packet) {
    _stats.dataPacketsReceived++;
    final hasStart = (packet.flags & kFlagStart) != 0;
    final hasEnd = (packet.flags & kFlagEnd) != 0;

    if (packet.seq == _recvSeqExpected) {
      if (hasStart) {
        _receiveBuffer = BytesBuilder(copy: false);
        _receiving = true;
      }

      if (!_receiving) {
        _stats.protocolErrors++;
        _log('data without START, dropping');
        return;
      }

      _receiveBuffer!.add(packet.payload);
      if (_receiveBuffer!.length > config.maxMessageBytes) {
        _stats.protocolErrors++;
        _log('message exceeds maxMessageBytes, dropping');
        _receiving = false;
        _receiveBuffer = null;
        return;
      }

      if (hasEnd) {
        final message = _receiveBuffer!.toBytes();
        _messages.add(Uint8List.fromList(message));
        _stats.messagesDelivered++;
        _stats.bytesDelivered += message.length;
        _receiving = false;
        _receiveBuffer = null;
      }

      _recvSeqExpected ^= 1;
      _sendAck(packet.seq);
      return;
    }

    _stats.duplicatePackets++;
    _sendAck(packet.seq);
  }

  void _handleAck(int seq) {
    _stats.ackPacketsReceived++;
    final inFlight = _inFlight;
    if (inFlight == null || inFlight.seq != seq) {
      return;
    }
    if (!inFlight.completer.isCompleted) {
      inFlight.completer.complete();
    }
    _inFlight = null;
    _sendSeq ^= 1;
  }

  void _sendAck(int seq) {
    final packet = TransportPacket(
      version: kProtocolVersion,
      type: kTypeAck,
      flags: 0,
      seq: seq,
      payload: Uint8List(0),
    );
    _sendPacket(packet);
  }

  void _log(String message) {
    if (_logger == null) {
      return;
    }
    _logger!('[$name] $message');
  }
}

class _InFlight {
  _InFlight({required this.seq, required this.completer});

  final int seq;
  final Completer<void> completer;
}
