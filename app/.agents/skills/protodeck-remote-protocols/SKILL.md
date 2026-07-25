---
name: protodeck-remote-protocols
description: Stateful remote and protocol-console workflow for ProtoDeck SSH terminal and saved profiles, integrated SFTP/SCP/Shell files, SMB, Telnet, transfer queues, TCP/UDP client/server, REST, WebSocket, SSE, MQTT, Bluetooth Classic and BLE/GATT debugging. Use when implementing or debugging connections, authentication, host trust, files, sorting, subscriptions, message send/receive logs, payload editors, reconnect, cancellation, permissions, or session cleanup.
---

# ProtoDeck Remote Protocols

Read [session-contracts.md](references/session-contracts.md) before changing a connection lifecycle,
credential, file panel, message timeline or transfer.

## Model a session, not a form submission

1. Define states for disconnected, connecting, connected/listening, stopping and failed. Add protocol
   states such as subscribed, streaming or discovering only where they carry real meaning.
2. Keep the connection/session object outside transient form rebuilds. Disable duplicate connect/start
   actions and make disconnect/stop reachable while work is pending.
3. Keep sent and received events in an ordered, bounded timeline with direction, timestamp, type/topic,
   size and decoded/raw views. A successful connection without a usable receive surface is incomplete.
4. Cancel readers, polling timers, subscriptions, sockets, channels and transfers on disconnect and
   dispose. Emit one terminal state and permit a clean reconnect.
5. Persist reusable profile metadata, not live sessions. Put passwords/private material/API secrets in
   secure storage and store only references in ordinary database rows.

## Preserve security boundaries

- Verify SSH host keys with TOFU. Block changed fingerprints until the user explicitly re-trusts.
- Never log passwords, private keys, Authorization headers, API keys, cookies or full MQTT credentials.
- Redact sensitive request values in error/export views while preserving a useful diagnostic preview.
- Quote/validate paths used by Shell/SCP fallback and never concatenate untrusted input into a general
  local shell command.
- Keep server/listener bind address and exposure visible. Default to the least exposed useful bind and
  warn before listening on all interfaces.

## Implement protocol workbenches

- SSH: saved cards support one-tap reconnect. Keep PTY resize and mobile special keys. Initialize the
  file surface after SSH authentication without blocking terminal usability.
- Router file access: try SFTP, then use the existing SCP/Shell file-panel fallback for SSH servers
  without an SFTP subsystem. Report which backend is active and why fallback occurred.
- SFTP/SMB/Shell files: keep directory-first stable sorting and explicit name/byte-size/timestamp
  ordering. Support progress, conflict policy, cancellation and actionable failures.
- REST: separate URL/query/path, headers, auth and body editors; provide raw/JSON/form modes, request
  preview, response status/headers/body/timing, and reusable environment variables without exposing
  secrets.
- WebSocket/SSE/MQTT: show connection state and ordered receive events. WebSocket sends text/binary;
  SSE assembles event/data/id/retry records; MQTT manages a visible subscription list, QoS/retain and
  topic-tagged messages.
- TCP/UDP: support client/server states, text/HEX payloads, encoding, local/remote endpoint display,
  receive framing expectations, repeat-send cancellation and bounded logs.
- Bluetooth: distinguish Classic discovery/RFCOMM from BLE scan/GATT. BLE details include advertised
  data, RSSI, services, characteristics, descriptors, properties, MTU and notification subscriptions.

## Verify with a real peer

Unit tests may validate parsing/state reducers, but SSH routers, SMB servers, MQTT brokers, SSE/WebSocket
streams and BT/BLE devices require peer interoperability checks. Record the peer, protocol mode,
disconnect/reconnect result and any Android permission/system-state dependency.
