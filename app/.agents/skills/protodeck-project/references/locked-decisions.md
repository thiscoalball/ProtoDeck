# Locked product decisions

Apply these until the user explicitly supersedes them.

- Product direction: a polished mobile network and developer protocol workbench, Android complete
  first, with honest platform limitations and local-first behavior.
- Product brand: `ProtoDeck`. User-visible names, public documentation and new architecture names
  must not revive legacy product branding. Internal platform identifiers require an explicit,
  migration-safe change instead of an incidental search-and-replace.
- Primary navigation: Home, Wi-Fi, Tools, Remote. Do not show History. Open Settings from the Home
  gear.
- Visual direction: clean bright surfaces, restrained sky/cobalt blue, generous spacing, modern
  automotive/smart-router hierarchy, minimal decorative gradients, and a usable dark mode.
- Home: internet state leads; local connectivity remains useful without public IPv4. Keep network,
  gateway and DNS summary compact. Put current Wi-Fi/cellular core signal history inside the primary
  status area and show a truthful network-quality assessment.
- Wi-Fi: dedicated primary tab with current connection, nearby networks, search/filter, details,
  signal sampling, channel occupancy, channel-width strength envelopes and CN-oriented channel
  recommendations. Label WLAN 2.4/5/6 GHz separately from cellular 4G/5G NR.
- Network status: green is reserved for verified success. A failed DNS or internet probe must change
  the aggregate card and the corresponding step icon; refresh must recompute, not retain stale green.
- Default targets: gateway for LAN-oriented tools when available; `baidu.com` for Traceroute and
  internet-oriented examples.
- SSH: saved profiles must allow one-tap reconnect. After connection, expose an integrated remote file
  panel. Try SFTP first and provide the implemented SCP/Shell listing fallback for router SSH servers
  without an SFTP subsystem.
- Stateful protocol tools: REST, WebSocket, SSE, MQTT, TCP/UDP and Bluetooth are debugging consoles,
  not single-submit forms. Preserve sent/received messages, connection/subscription state and
  structured payload display during the live session.
- No site/network profiles, LAN asset inventory or “recent three actions” unless requested again.
- Toolbox categories are Wi-Fi, Diagnostics, Traffic & performance, Remote & services, IP &
  addressing, API & protocols, Data & conversion, Security & identity, and Backend engineering.
