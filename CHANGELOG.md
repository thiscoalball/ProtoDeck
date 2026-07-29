# Changelog

All notable changes to ProtoDeck will be documented in this file. The format follows Keep a
Changelog and releases use Semantic Versioning where practical.

## [Unreleased]

### Added

- Planned 1.0.1 network and Wi-Fi professionalization work is tracked in
  `docs/changes/1.0.1-network-wifi.md`.
- Desktop DHCP/static IPv4, DNS, metric and static-route profiles with multi-adapter selection,
  pre-apply differences, ARP conflict warnings, post-write field verification and a manual
  pre-change restore point. Connectivity checks are independently repeatable and never roll back a
  successfully written configuration. Android remains read-only because ordinary apps cannot
  reliably apply system Wi-Fi IP settings.
- Per-BSSID Wi-Fi signal monitoring, access-point capability/security inspection, explainable
  channel recommendations, connection verification and deeper roaming diagnostics.
- Pull requests build and retain Android, Linux x64 and Windows x64 Release-mode artifacts with a
  Debug channel label; version tags retain the Release channel label.
- Public repository documentation, privacy and security policies.
- Platform capability and Android permission documentation.
- Contributor, issue and pull-request templates.
- Central third-party attribution index.

### Security

- Removed machine-specific MCP/editor integration files and local absolute paths from published
  history.

### Excluded

- Floor-plan site surveys and Wi-Fi heatmaps are intentionally outside the 1.0.1 scope.

## [1.0.0] - Unreleased

- Initial public development baseline.
