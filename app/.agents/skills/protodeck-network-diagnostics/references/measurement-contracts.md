# Network measurement contracts

## Current network and home diagnosis

- `connected` means Android reports an active network; it does not promise DNS or endpoint reachability.
- Validated internet, DNS lookup, gateway probe and external endpoint probe are separate checks with
  their own timestamps and errors.
- Public IPv4/IPv6 lookup is optional enrichment. NAT, CGNAT, IPv6-only access and provider blocking
  are normal conditions.
- Recompute the displayed aggregate on refresh. Use success only when required checks passed; use
  warning for partial connectivity and error for verified failure. Never preserve a previous green
  border after a failed rerun.
- Network quality is evidence-based. Include the metric window and avoid a confident score when too
  few samples exist.

## Wi-Fi and cellular

- Wi-Fi RSSI uses dBm, normally within `-100..0`; a less-negative value is stronger.
- Wi-Fi signal history samples foreground current-connection RSSI, records timestamps, avoids
  duplicate timers, survives a single-point series, and resets or marks a source change on BSSID.
- Nearby AP scans are snapshots and can be throttled/cached. Show age. Group/filter by 2.4, 5 and
  6 GHz and identify BSSID independently of SSID.
- Channel graphs use channel numbers on the visible axis. A width/strength envelope derives its
  center from frequency/channel and spans the reported 20/40/80/160/320 MHz width; it is not a count
  bar chart.
- CN recommendations must consider legal candidate channels, observed co-channel/overlap load,
  supported bandwidth and device capability. Present advice, not an automatic configuration change.
- Cellular type comes from telephony data. Show useful available values such as RSRP, RSRQ, SINR/RSSNR,
  RSSI, CQI, timing advance, band/channel and cell identity, but omit unsupported values instead of
  substituting zero. Wi-Fi 5 GHz is never labeled 5G NR.

## Ping

- Finite mode stops after `count`; continuous mode ignores count until the user stops.
- Each sample records sequence, response/timeout/error, elapsed time and available TTL. Statistics use
  successful RTT samples for min/avg/max and an explicitly defined jitter calculation; loss uses sent
  versus received.
- ICMP, TCP, UDP Echo and UDP Probe have different success semantics. Do not merge refused,
  unreachable and timeout into a generic boolean.
- The latency chart accepts empty, one-point and long-running series. It uses a zero baseline and a
  readable dynamic upper bound; it must not disappear because minY/maxY are equal.

## iPerf3

- Mode and arguments agree: Client requires `-c <host>` and excludes `-s`; Server requires `-s` and
  excludes `-c`.
- The Dart parser rejects shell syntax and unsupported/file/daemon parameters. Numeric limits remain
  bounded.
- Native execution occurs off the main thread and only one session is active. Client connection has a
  bounded timeout; Server exposes a waiting state instead of looking frozen.
- Stream standard-style interval lines while running. Structured samples power throughput, retransmit,
  UDP loss and jitter charts; final JSON is supplemental, not the only output.
- Stop must wake/close blocking native work, emit a terminal event once, stop the foreground service
  and allow a clean rerun.

## Traceroute, GeoIP and maps

- Sort and render by numeric hop. Enrichment completion order must not change route order.
- Retain missing hops in the textual list. Draw only coordinate-bearing public hops and connect each
  displayed point to the next point in hop order.
- Use geographic projection for an actual map. The offline overview may normalize coordinates to a
  bounded canvas, but must include visible geographic context and correct latitude/longitude order.
- Provider success without coordinates is “location known textually, not mappable”; provider/network
  failure is a different state.

## LAN and discovery

- Suggest the active subnet, default to `/24`, require confirmation for expansion and cap at `/20`.
- Use bounded work queues; do not create one unbounded Future/socket per address/port.
- Publish progress and partial devices, deduplicate by stable address, and stop scheduling new work
  immediately on cancellation.
- MAC/OUI is shown only when a real MAC was obtained. Unknown is not a generated MAC.
