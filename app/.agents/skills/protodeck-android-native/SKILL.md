---
name: protodeck-android-native
description: Android-native implementation and debugging rules for ProtoDeck Kotlin APIs, the nettools/native MethodChannel, Wi-Fi/Connectivity/Telephony, Bluetooth Classic and BLE, SMBJ, foreground services and notifications, permissions, JNI/CMake and embedded libiperf. Use whenever changing AndroidManifest.xml, Gradle, Kotlin, C/C++, platform payloads, native task threading, cancellation, SDK/ABI behavior, or a Dart service that calls Android.
---

# ProtoDeck Android Native

Read [channel-contract.md](references/channel-contract.md) before modifying a method name, argument,
result payload, permission or lifecycle.

## Change both sides as one contract

1. Locate the Dart caller and Kotlin handler before editing. Keep method names, key spelling, numeric
   types, nullability, units and error semantics synchronized.
2. Prefer a typed model/adapter at the Dart boundary. Do not spread raw `Map<Object?, Object?>` parsing
   into pages.
3. Run blocking network, filesystem, SMB, Bluetooth connection and native iPerf work off the Android
   main thread. Deliver each MethodChannel result exactly once on the UI thread.
4. Give every long native task an idempotent stop path that wakes blocking work, releases resources,
   reaches a terminal state and supports another start.
5. Handle activity/service destruction, permission denial, Bluetooth/Wi-Fi disabled state and network
   changes without leaking receivers, locks, executors, GATT objects, sockets or notifications.

## Respect Android capability boundaries

- Keep minimum Android 10/API 29 unless the user explicitly changes product support.
- Acquire Wi-Fi/Bluetooth/location permissions at feature entry. Preserve pre-Android-12 and
  Android-12+ permission branches and explain when system Location must also be enabled.
- Wi-Fi scan results can be cached/throttled. Never claim `startScan()` means fresh results.
- Read active route, capabilities and link properties from `ConnectivityManager`. Do not equate public
  IP lookup with network connectivity.
- Keep WLAN band and telephony generation separate. Telephony metrics may be unavailable by modem,
  carrier, permission or Android version; return null/omitted fields rather than invented zeros.
- Use `CHANGE_WIFI_MULTICAST_STATE` only around local discovery and always release its lock.
- Keep foreground-service type, manifest permission, notification channel and actual task purpose in
  agreement. Start only from user-visible work and always expose stop.

## Maintain JNI and libiperf safely

- Dart validates the command; JNI accepts an argument array, never a command string for shell parsing.
- Keep one active native session. Protect global state and the event queue consistently.
- Do not block JNI/main threads waiting for a Client connection or Server peer. Use a worker and emit
  waiting/interval/final/error events.
- Stop must interrupt sockets/libiperf work rather than only setting a flag that blocking code never
  observes. Free native allocations and clear state on all exit paths.
- Preserve embedded upstream license/version information and avoid editing vendored iPerf sources when
  a small facade patch is sufficient.
- Build/check every supported ABI affected by CMake changes; a successful host/unit test is not an
  Android native-load test.

## Verify platform behavior

Use focused Dart tests for payload parsing and Android build checks for compilation. Then test relevant
permission/system states on physical Android versions. Wi-Fi scan, cellular metrics, BLE, SSH-router
fallback, SMB and iPerf interoperability cannot be accepted from an emulator-only result.
