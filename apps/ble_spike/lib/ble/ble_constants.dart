/// BLE Constants for PRSM Chat
/// 
/// UUIDs from Transport-Spec v1 (docs/transport-spec-v1.md)
/// These are used by both Central and Peripheral roles.

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// GATT Service UUID for PRSM Chat
/// From: docs/transport-spec-v1.md
final UUID kChatServiceUuid = UUID.fromString('0BBB59CC-506F-4686-B5C3-AED9A63DE1C3');

/// RX Characteristic (Central -> Peripheral)
/// Properties: Write, Write Without Response
/// The Central writes data here, Peripheral receives it
final UUID kRxCharacteristicUuid = UUID.fromString('8D92A77A-10E5-425D-97A7-18195AEE9A81');

/// TX Characteristic (Peripheral -> Central)
/// Properties: Notify
/// The Peripheral notifies data here, Central receives it
final UUID kTxCharacteristicUuid = UUID.fromString('9A27A89D-0405-42D0-9E8A-A10002EA6BA1');

/// Legacy UUIDs (for backwards compatibility during migration)
/// TODO: Remove after full migration to new UUIDs
const String kLegacyChatServiceUuid = 'F00D0001-1212-EFDE-1523-785FEABCD123';
const String kLegacyWriteCharUuid = 'F00D0002-1212-EFDE-1523-785FEABCD123';
const String kLegacyNotifyCharUuid = 'F00D0003-1212-EFDE-1523-785FEABCD123';

/// MTU and payload sizing (from Transport-Spec)
const int kTargetMtu = 185;           // iOS typical MTU
const int kTransportHeaderSize = 4;   // version(1) + type(1) + flags(1) + seq(1)
const int kMaxPayloadSize = 176;      // kTargetMtu - overhead - kTransportHeaderSize
const int kMaxMessageBytes = 64 * 1024; // 64 KiB max message size
