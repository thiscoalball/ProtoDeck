# Android channel and lifecycle contract

## Location

- Channel name: `nettools/native`
- Kotlin dispatcher: `android/app/src/main/kotlin/com/nettools/nettools_mobile/MainActivity.kt`
- Dart network adapter: `lib/services/native_network_service.dart`
- Other Dart adapters: `smb_service.dart`, `bluetooth_debug_service.dart`, local-discovery calls
- Native iPerf facade: `IperfNative.kt`, `cpp/nettools_iperf_jni.c`, `cpp/CMakeLists.txt`
- Foreground task: `NetworkTaskService.kt` and `AndroidManifest.xml`

## Existing method families

| Family | Methods/intent |
|---|---|
| Network | `getNetworkContext`, `scanWifi`, `runPing`, `probePathMtu`, `runTraceroute`, `cancelTraceroute` |
| iPerf | `runIperf`, `stopIperf`, `isIperfRunning`, `pollIperfEvent` |
| SMB | `smbConnect`, `smbList`, `smbMkdir`, `smbDelete`, `smbRename`, `smbUpload`, `smbDownload`, `smbDisconnect` |
| Bluetooth | status/bonded/event polling; Classic scan/connect/server/send/stop; BLE scan/connect/GATT read/write/notify/server operations |
| Discovery | `acquireMulticastLock`, `releaseMulticastLock` |
| Foreground work | `startForegroundTask`, `stopForegroundTask` |

Before adding a parallel method, search both Dart and Kotlin for an existing capability. If a payload
becomes complex or frequently changes, introduce a versioned/typed boundary rather than adding
uncoordinated map keys.

## Threading and result rules

- `configureFlutterEngine` runs on the main thread. Never perform blocking work directly in its handler.
- Complete a `MethodChannel.Result` once. Move success/error delivery to the UI thread.
- Avoid unbounded cached-thread growth for scans or per-host work; use an owned bounded executor/queue
  when concurrency can multiply.
- Cancellation is idempotent and safe before start, during blocking I/O, after completion and during
  activity teardown.
- Event polling queues are bounded and include an explicit terminal event. Clear old-session events
  before a new run or tag events with a session id.

## Permission and system-state matrix

- Wi-Fi connection/scan: network and Wi-Fi state permissions; fine location and system Location where
  Android requires them; `NEARBY_WIFI_DEVICES` on Android 13+ as applicable.
- Bluetooth ≤ Android 11: legacy Bluetooth plus location requirements. Android 12+: scan/connect/
  advertise runtime permissions by operation.
- Notifications: request `POST_NOTIFICATIONS` where needed, but task correctness must not depend on a
  silently denied prompt.
- Local discovery: acquire/release multicast lock around actual work, not app lifetime.
- Storage: use app-private files or SAF grants. Do not add all-files access for convenience.

## Native acceptance checks

- Clean compile and native library packaging for at least `arm64-v8a`; retain configured debug ABI
  behavior.
- Install and launch on a physical API 29+ Android device.
- Exercise permission denied, denied permanently, granted, radio disabled and app background/return.
- For iPerf, run Android ↔ Linux in Client and Server, TCP and UDP, then stop during connection/wait and
  rerun without restarting the app.
