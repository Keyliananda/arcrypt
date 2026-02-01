# Transport Spec v1 (MVP) - PRSM

Status: draft (2026-02-01)
Scope: transport over BLE GATT between Central (iOS) and Peripheral (Android).

## Goals
- Reliable, ordered delivery of byte payloads over BLE notifications/writes.
- Chunking of larger payloads to fit iOS MTU constraints.
- Simple stop-and-wait reliability (no pipelining).

## Non-goals
- High throughput or streaming.
- Resume after disconnect.
- Multiplexing or prioritization.

## BLE roles (MVP)
- Android acts as Peripheral (GATT server).
- iOS acts as Central (GATT client).
- The transport is symmetric, but only the Peripheral hosts the GATT service in MVP.

## GATT definitions
Service UUID: `0BBB59CC-506F-4686-B5C3-AED9A63DE1C3`

Characteristics:
- RX (Central -> Peripheral): `8D92A77A-10E5-425D-97A7-18195AEE9A81`
  - Properties: Write, Write Without Response
  - Permissions: Writeable
- TX (Peripheral -> Central): `9A27A89D-0405-42D0-9E8A-A10002EA6BA1`
  - Properties: Notify
  - Permissions: Readable (optional), Notifiable

Connection sequence:
1) Central connects to Peripheral.
2) Central subscribes to TX notifications (CCCD).
3) Transport frames flow via RX writes and TX notifications.

## MTU and payload sizing
- Target ATT payload limit: 180 bytes (for iOS compatibility).
- Transport header: 4 bytes.
- Max data per transport packet: 176 bytes.
- If negotiated MTU allows more, still cap at 180 bytes in MVP for parity.

## Packet format (v1)
All multi-byte values are unsigned, little-endian.

Header (4 bytes):
- byte0: version (0x01)
- byte1: type (0x01 = DATA, 0x02 = ACK)
- byte2: flags (bit0 = START, bit1 = END, others reserved)
- byte3: seq (0x00 or 0x01, alternating bit)

Payload:
- For DATA: 0..176 bytes of opaque payload (encrypted at higher layer).
- For ACK: empty.

Examples:
- Single-chunk message: START|END set, DATA payload <= 176 bytes.
- Multi-chunk message: first chunk START, middle chunks no flags, last chunk END.

## Stop-and-wait protocol (alternating bit)
Each direction maintains its own state:
- send_seq: 0 or 1
- recv_seq_expected: 0 or 1
- in_flight: bool

Send flow (DATA):
1) If in_flight, wait.
2) Build DATA packet with seq = send_seq.
3) Transmit over RX (write) or TX (notify), start ack timer.
4) On ACK with matching seq: in_flight = false, send_seq ^= 1.
5) On timeout: retransmit (up to MAX_RETRY), else fail session.

Receive flow (DATA):
- If seq == recv_seq_expected:
  - Accept payload, append to current message buffer.
  - If START flag: reset buffer before append.
  - If END flag: deliver assembled message to higher layer.
  - Toggle recv_seq_expected ^= 1.
  - Send ACK for this seq.
- Else (duplicate/out-of-order):
  - Ignore payload, send ACK for received seq.

Receive flow (ACK):
- If seq matches current in-flight packet, complete send and advance send_seq.
- Else ignore (stale ACK).

## Reassembly rules
- START flag opens a new message buffer (discard any partial buffer).
- END flag closes the buffer and delivers the assembled message.
- If a DATA packet arrives with no START and no active buffer, treat as protocol error and drop; sender will retry until timeout.
- If the assembled message exceeds MAX_MESSAGE_BYTES (default 64 KiB), abort the session.

## Session reset rule
- On disconnect: drop in-flight packets, clear buffers, reset seq to 0.
- No resume in MVP. A new connection always starts a new transport session.

## Checks (performed)
- Doku-check: packet format, MTU math, and stop-and-wait flow reviewed for consistency with `docs/security-spec-v1.md`.
- Runtime checks: not run (transport harness not implemented yet).

## Test plan (vorerst nicht)
- [vorerst nicht] Transport harness: send 1/5/10 KB payloads, verify reassembly.
- [vorerst nicht] Loss/retry: inject 10-30% drops, verify retransmission and duplicate filter.
- [vorerst nicht] Disconnect mid-message: ensure buffer clears and no resume.

## Open decisions
- MAX_RETRY and ACK timeout defaults.
- MAX_MESSAGE_BYTES final value.
