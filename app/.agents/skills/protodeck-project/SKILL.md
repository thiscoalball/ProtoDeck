---
name: protodeck-project
description: Repository-wide architecture, scope, and change-safety workflow for the ProtoDeck/NetTools Flutter application. Use for every code change, bug diagnosis, refactor, feature addition, dependency update, project review, documentation change, or release task under Nettools, and combine it with the narrower network, remote-protocol, Android-native, UI-UX, and verification skills as applicable.
---

# ProtoDeck Project

Work from `Nettools/app` unless a command explicitly targets the repository root.

## Start safely

1. Read `../../../../AGENTS.md` and respect its source-of-truth order.
2. Run `git -C ../ status --short` and preserve unrelated changes.
3. Read [architecture.md](references/architecture.md). For navigation, product behavior, naming,
   privacy or defaults, also read [locked-decisions.md](references/locked-decisions.md).
4. Inspect the entire owning path: page/widget → state/provider → service/model → native bridge or
   storage → focused tests.
5. Load the additional project skill matching every touched domain.

## Route the task

- Network measurement or connectivity: use `$protodeck-network-diagnostics`.
- Stateful remote/API/Bluetooth work: use `$protodeck-remote-protocols`.
- Android/Kotlin/JNI/permission work: use `$protodeck-android-native`.
- Any user-visible layout or interaction: use `$protodeck-ui-ux`.
- Before handoff: use `$protodeck-verify-release`.

## Implement within the architecture

- Keep reusable protocol/calculation logic in `lib/services`, data shapes in `lib/models`, persisted
  data in `lib/data`, platform calls behind service adapters, and pages in `lib/ui/pages`.
- Register a new tool consistently in `lib/ui/tool_catalog.dart` and `lib/ui/tool_launcher.dart`;
  include aliases/search terms and a focused test where practical.
- Keep widgets declarative. Move parsing, networking, storage, cancellation and retry semantics out
  of large build methods when extending a feature.
- Model unavailable and failure states explicitly. Do not replace missing native values with plausible
  constants or reuse a stale value without a cached timestamp/label.
- Preserve compatibility of persisted tables and platform-channel payloads. Add migrations before
  increasing Drift schema version; regenerate generated files instead of hand editing them.
- Avoid broad dependency upgrades. Explain and verify any new package, Android permission, service,
  native ABI, or network provider.

## Finish

Review the diff for accidental renames, secret material, generated build output, overly broad
permissions and orphaned timers/sockets. Then select the verification tier from
`$protodeck-verify-release` and report device-only checks separately.
