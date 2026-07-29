---
name: protodeck-network-diagnostics
description: Reliable network measurement workflow for ProtoDeck Wi-Fi and cellular context, internet diagnosis, ICMP/TCP/UDP Ping, DNS, iPerf3, Traceroute and route maps, GeoIP, STUN/public IP, port/LAN scanning, local discovery and network quality. Use when implementing, debugging, reviewing, or redesigning any connectivity feature, signal chart, default target, result statistic, cancellation flow, scan behavior, or connected/unavailable status.
---

# ProtoDeck Network Diagnostics

Read [measurement-contracts.md](references/measurement-contracts.md) before changing a result model,
status, default target, chart or platform measurement.

## Diagnose the correct layer

1. Reproduce or trace the full flow from the page to service/model and, when used, the
   `nettools/native` implementation.
2. Classify the issue as acquisition, permission, parsing, task lifecycle, aggregation, cache,
   presentation or platform limitation. Do not patch presentation to conceal acquisition failure.
3. Define the observation contract: source, units, timestamp, success evidence, unavailable reason,
   timeout, cancellation and stale-data behavior.
4. Implement explicit states: idle → validating → running → stopping → completed/failed/cancelled.
   Prevent concurrent starts unless the feature intentionally supports them.
5. Cancel timers, streams, isolates, sockets, processes and foreground notifications on stop/dispose.
6. Add a deterministic service/model test plus a focused widget test for visible regressions.

## Preserve measurement truth

- Treat local link, gateway/DNS availability, validated internet capability and public-address lookup
  as separate evidence. A failed public-IP provider must not mark the network offline.
- Preserve the active default route and VPN indication. Show underlying Wi-Fi/cellular context when
  available without pretending it is the direct egress.
- Label Wi-Fi 2.4/5/6 GHz separately from cellular LTE/NR. Keep dBm and cellular metric units intact.
- Treat SSID/BSSID absence as permission/platform state. A scan-result BSSID match may enrich an
  unavailable SSID, but never invent an SSID.
- Mark Wi-Fi scans with collection time and cached/throttled status. Android cannot guarantee active
  scans every few seconds; current-connection RSSI may be sampled independently in the foreground.
- Drive Wi-Fi band visibility and channel recommendations from runtime radio/regulatory capability;
  never infer a country from UI language. Preserve every BSSID when grouping by SSID.
- Treat desktop DHCP/static IPv4 changes as transactional: validate, snapshot, apply, verify and
  rollback. Do not expose an Android static-IP action that an ordinary app cannot complete.
- Bound LAN/port scan range, concurrency and rate; publish incremental progress and make stop prompt.
- Keep UDP Probe timeout as unknown, not proof that a port is closed.

## Implement protocol-specific behavior

- Ping: support finite and continuous modes, requested interval/timeout/size/IP family, per-sample
  results, loss, min/avg/max and jitter. Keep partial statistics after stop.
- iPerf: validate allowlisted arguments in Dart, pass an argument array to libiperf, run one native
  session, stream human-readable interval output and structured samples, and stop native blocking I/O.
  Never run command text through a shell.
- Traceroute: preserve hop number and probe order, enrich public hops without reordering them, connect
  map points sequentially by hop, and keep private/unknown hops in the list.
- GeoIP/maps: distinguish provider failure from missing coordinates. Maps used in China must not rely
  solely on an inaccessible tile endpoint; the offline geographic overview remains a usable fallback.
- Network diagnosis: compute aggregate severity from current step results every run. DNS or internet
  failure cannot leave the outer card green or its step marked successful.

## Use safe defaults

Prefill the current gateway only for LAN-oriented tools. Use `baidu.com` for Traceroute and other
internet-path examples. Never silently replace user-entered targets when the network changes.
