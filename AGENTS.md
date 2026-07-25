# ProtoDeck repository instructions

These instructions apply to the entire ProtoDeck repository. The Flutter app lives in
`app/`. ProtoDeck is the public product brand. Some internal package and compatibility
identifiers still use the historical project name; change those only as a coordinated migration,
not as an incidental search-and-replace.

## Mandatory project skills

Before editing, read every applicable `SKILL.md` completely:

- Any repository change, diagnosis, refactor, or review: `app/.agents/skills/protodeck-project/SKILL.md`
- Wi-Fi, cellular, current network, Ping, DNS, iPerf, Traceroute, GeoIP, LAN discovery, ports or network quality: `protodeck-network-diagnostics`
- SSH/SFTP/SCP/Shell files, SMB, Telnet, TCP/UDP, REST, WebSocket, SSE, MQTT, BT or BLE: `protodeck-remote-protocols`
- Kotlin, Android API, permissions, foreground service, MethodChannel, JNI/CMake or libiperf: `protodeck-android-native`
- Page layout, visual hierarchy, charts, touch interaction, status presentation or responsive UI: `protodeck-ui-ux`
- Tests, generated code, APK, dependency/release preparation or final verification: `protodeck-verify-release`

Skills are composable. A Wi-Fi page change normally requires project + network + UI; an iPerf JNI
change requires project + network + Android native + verification.

## Source-of-truth order

1. The user's latest explicit request and locked decisions below.
2. Executable code, tests, platform manifests and build configuration.
3. This file and project skills.
4. The current README and dependency documentation as supporting context.

Do not reintroduce an old requirement merely because it remains in an early document.

## Non-negotiable product and engineering rules

- Never fabricate network, Wi-Fi, cellular, Bluetooth, GeoIP, OUI, file, or diagnostic data. Show
  unavailable, permission-required, cached, unsupported, timeout, refused and unknown as different
  states.
- Internet usability is not determined by the presence of a public IPv4 address. A phone behind
  NAT/CGNAT or on IPv6-only access can be online. Public IP is secondary information.
- Keep the primary navigation to Home, Wi-Fi, Tools and Remote. History stays hidden and disabled;
  Settings is entered from the Home gear unless the user explicitly changes this decision.
- Android is the complete first platform, minimum API 29. Preserve honest iOS capability gaps.
- Wi-Fi 5 GHz is a WLAN band, never “5G NR”. Cellular radio generation and WLAN band are separate.
- Every long operation must have validation, running, stop/cancel, completion, failure and disposed
  behavior. Do not block the Flutter UI isolate or Android main thread.
- iPerf command text is parsed into an allowlisted argument array. Never execute it as a shell.
- Request sensitive permissions at the feature boundary, explain why, handle denial, and avoid
  broad storage/root permissions. Store secrets only through the existing secure-storage design.
- Default a gateway only for tools that commonly target the LAN (for example Ping, SSH, Telnet,
  LAN/port tools). Do not prefill a private gateway for Traceroute; its default is `baidu.com`.
- Preserve user changes and unrelated dirty-worktree edits. Do not edit generated
  `lib/data/app_database.g.dart` manually.
- Treat scans and remote operations as authorized-administration features. Keep bounded ranges,
  concurrency, timeouts and clear stop controls.

## Working agreement

Inspect the full path from UI to service/model/native layer before changing behavior. Fix the cause
at its owning layer instead of masking it in the widget. Add or update focused tests for regressions,
then run the risk-appropriate verification skill. State which checks could not run on this SSH server
or require a physical Android device.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
