# Existing tool depth audit

Use this workflow when asked to strengthen the current toolbox. Do not add a catalog entry unless the
user explicitly requests a new tool.

## Inventory first

Treat `tool_catalog.dart` as the bounded inventory. For every entry, trace launcher → page → service →
model/native adapter → focused tests. Include tabs and modes inside a page; a REST/WebSocket/SSE/MQTT
workbench is one catalog tool with four independently audited modes.

Record these dimensions mentally or in task notes:

- input validation, presets and safe defaults;
- typed result completeness and protocol correctness;
- progress, timeout, cancellation and disposal;
- filtering, sorting, search, comparison and drill-down;
- per-value copy, full-report copy and structured export where results are reusable;
- safe draft restoration without restarting work;
- empty, partial, permission, dependency and platform-limited states;
- Chinese/English rendering and dynamic result localization;
- boundary, parser and cancellation tests.

## Decide what to deepen

Prefer primary protocol specifications and official product documentation. Extract interaction and
diagnostic principles, not competitor branding, text or layouts. Strengthen the existing owning page
instead of creating a neighboring one.

Prioritize in this order:

1. Incorrect, misleading or fake-success behavior.
2. A task that cannot stop, times out ambiguously or leaks a socket/subscription.
3. Results that omit information already available in the service/model.
4. Results that cannot be searched, sorted, copied, exported or handed to a related tool.
5. Thin presets, explanations and boundary handling.
6. Visual polish that does not improve diagnosis.

Do not claim unsupported precision. Examples: one STUN Binding does not prove a legacy NAT type;
desktop endpoint ownership is not per-process byte accounting; a sent WOL datagram does not prove the
device woke; cached Wi-Fi scan data must retain its timestamp.

## Category expectations

- Network/Wi-Fi: show source, timestamp and interface; distinguish reachability, Internet, DNS and
  public-address availability; support stable time-series axes and honest platform limits.
- Diagnostics: expose sampling parameters, cancellation, per-sample details, summary statistics and
  a reusable report. Preserve protocol-specific fields such as DNS section/TTL, NTP LI/stratum/root
  distance, port state/banner and traceroute hop ordering.
- Traffic/capture: separate interface totals, endpoint ownership and enhanced accounting. For offline
  captures offer packet filters plus protocol hierarchy, I/O series, endpoints and conversations.
- Remote/services: keep explicit connection lifecycles, session switching, structured logs and
  transfer progress. Never persist secrets in ordinary drafts.
- IP/addressing: use exact integer arithmetic, label standards/special ranges and make each result row
  copyable.
- API/protocol: preserve workspaces, non-secret history and environment variables; render structured
  payloads by detected content type and keep raw/hex access.
- Data/security/backend: provide examples, batch paths, copyable structured output, actionable parse
  errors and engine/algorithm limitations.

## Finish the audit

Run formatting, static analysis, localization checks and focused tests for every changed category.
Then run the full suite and a Release build appropriate to the host. Update this reference only when
the reusable audit contract changes; do not turn it into a feature changelog.
