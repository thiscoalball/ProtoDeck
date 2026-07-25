# Verification matrix

| Change area | Minimum automated checks | Additional acceptance |
|---|---|---|
| Pure service/model | Analyze + related unit tests | Boundary/error cases |
| Flutter page/widget | Analyze + focused widget test | Narrow phone, large text, dark theme |
| Network task | Related service/widget tests + full suite | Stop, timeout, rerun, network change |
| Drift schema | Generator + analyze + DB tests | Migration from previous schema |
| OUI asset/updater | OUI tests + integrity checks | Offline lookup, update cancel/rollback |
| Kotlin/channel | Analyze + Android debug build | Permission/device/API-version matrix |
| JNI/CMake/iPerf | Android build for affected ABIs | Physical device ↔ independent peer |
| SSH/SMB/API/MQTT/BT | Parser/state tests + full suite | Real server/broker/device reconnect |
| Release metadata | Full suite + APK build | Signing, version, package ID, notices |

## Public repository hygiene

Review tracked content, not local `.git`, toolchains, build caches or IDE state. Look for:

- absolute home/workspace paths and operating-system user directories;
- personal names/emails, internal domains, private IPs used as real infrastructure, tokens and keys;
- screenshots/logs containing SSIDs, BSSIDs, phone numbers, account names or device identifiers;
- competitor-comparison language or comments that describe the product as a clone;
- generated binaries and large source downloads that are not intentionally versioned;
- required open-source/data licenses accidentally removed during cleanup.

Use neutral examples such as `192.0.2.1`, `198.51.100.0/24`, `example.com` and placeholder accounts in
public documentation and tests when a real endpoint is unnecessary.
