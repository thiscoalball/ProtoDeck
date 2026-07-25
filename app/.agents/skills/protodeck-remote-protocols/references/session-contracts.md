# Stateful protocol contracts

## Shared lifecycle

- Every start/connect operation has one owner and one cancellation path.
- UI state derives from the active session, not button labels or optimistic color alone.
- Errors retain protocol context and remain actionable: authentication, trust, DNS, timeout, refused,
  unsupported subsystem, permission, remote close and local cancellation are distinct.
- Reconnect creates fresh readers/writers and clears stale terminal flags. Do not reuse a closed socket
  or completed stream subscription.
- Message/log buffers are bounded. Batch UI updates under high traffic to prevent rebuild storms.

## SSH and files

- A successful SSH shell does not guarantee SFTP. Many routers omit or misconfigure the SFTP subsystem.
- Preferred backend order after SSH authentication:
  1. Start and probe SFTP with an actual directory operation.
  2. If subsystem startup/probe fails, activate the existing SCP/Shell file backend over a
     separate SSH session/channel where practical.
  3. Keep the terminal connected even if all file backends fail; show the concrete failure and retry.
- Shell listing must handle spaces, Unicode, symlinks and missing metadata defensively. Do not parse a
  locale-dependent decorative `ls` format when a stable command/encoding is available.
- File sorting always keeps directories first. Within each group, compare normalized name, numeric
  byte size or epoch timestamp; use name as a stable tie-breaker and show ▲/▼.
- Upload/download/delete/rename/chmod must update or refresh the affected view only after confirmed
  completion. Transfer state includes queued/running/paused/completed/failed/cancelled.
- Profile storage includes host, port, username, auth type and display name. Secret references and
  known-host fingerprints remain separate.

## REST and realtime APIs

- Build a request from structured fields; show the final request preview so encoding and injected
  headers are inspectable.
- Preserve duplicate query/header keys when protocols permit them. Disable a row without deleting it.
- Body modes are mutually explicit: none, JSON, text, XML, form URL encoded and multipart. Formatting
  must not silently change bytes in raw mode.
- Response view preserves status, headers, raw bytes/decoded text, formatted JSON where valid, size and
  timing phases. Invalid JSON remains viewable as text.
- WebSocket logs connection/open/close/error and every text/binary frame. Sending is disabled until open.
- SSE parses records separated by blank lines, joins multiple `data:` lines and retains event/id/retry.
- MQTT subscriptions are first-class rows with topic filter and QoS. Received messages show topic,
  QoS, retained/duplicate flags, timestamp and decoded/raw payload.

## TCP/UDP and Bluetooth

- TCP Server may own multiple clients; label each peer and let the user choose broadcast or one peer.
- TCP is a byte stream. Do not imply one write equals one receive message unless a delimiter/length
  framing mode was explicitly configured.
- UDP retains sender endpoint per datagram. UDP Client may send without claiming a persistent session.
- BLE scanning requires Android permission and Bluetooth/system state. Deduplicate by device address
  while updating RSSI and advertisement timestamps.
- Discover GATT only after connection; preserve service/characteristic UUIDs and properties. Notify and
  indicate are subscriptions with explicit enabled state and teardown.
- Bluetooth Classic and BLE use different discovery/connection paths and must never share misleading
  connected indicators.
