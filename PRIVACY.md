# Privacy

Last updated: 2026-07-27

ProtoDeck is a local-first network diagnostics and protocol workbench. This document describes the
behavior of the open-source application in this repository. A distributor that modifies the app or
adds services is responsible for documenting those changes.

## Data stored on the device

Depending on the features used, ProtoDeck may store:

- preferences, theme and provider configuration;
- saved SSH/SMB connection profiles and trusted SSH host fingerprints;
- API workspaces, request templates and sent-message history;
- transfer jobs, tool state and bounded diagnostic output;
- GeoIP cache entries and the local IEEE OUI database;
- credentials, private keys and API secrets in the operating system's secure storage.

Terminal output is not intended as telemetry and is not uploaded by ProtoDeck. Users should still
avoid saving secrets in request bodies, message history, filenames or profile names.

## Data sent over the network

ProtoDeck does not include advertising, analytics or behavioral telemetry SDKs. Network traffic is
created when the user runs a diagnostic, opens a remote connection, starts a protocol client, checks
for OUI updates, or when the dashboard calls a configured connectivity/provider endpoint.

The destination service necessarily receives the source IP address and normal protocol metadata. A
query may additionally contain an IP address, domain, DNS question, map tile coordinate or other
target entered by the user. Default providers are listed in [docs/permissions.md](docs/permissions.md).
Their operators process requests under their own terms and privacy policies.

ProtoDeck does not operate a first-party account service or synchronization backend in this source
tree.

## Device and network visibility

With explicit operating-system permission, ProtoDeck can inspect nearby Wi-Fi/Bluetooth broadcasts,
network interfaces, cellular signal metrics, installed application identity and device traffic
counters. This information is used to render the requested local diagnostic view. Android and
desktop operating systems may restrict or aggregate these values.

Starting a server or receiver makes the chosen device port reachable according to the selected bind
address, current network and firewall policy. Incoming peers may send data that is retained in the
current session or local history.

## Retention and deletion

Saved profiles, workspaces and histories should be removed through their corresponding application
controls where available. Clearing ProtoDeck's application data or uninstalling the application
removes ordinary local app data. Secure-storage behavior can also depend on the operating system and
device backup policy.

Exported files, downloaded files, packet captures and user-selected external documents remain in
their selected locations until the user deletes them.

## Security

ProtoDeck uses platform secure storage for supported secrets and SSH trust-on-first-use host-key
verification. No client can eliminate all risk: verify remote fingerprints, avoid untrusted public
networks, review listener bind addresses and do not import unknown packet captures or configuration
files without appropriate precautions.

Security vulnerabilities should be reported through the private process in [SECURITY.md](SECURITY.md),
not through a public issue.

## Changes

Material changes to this document should be recorded in the repository history and release notes.
