# Developer toolbox architecture

## Discovery taxonomy

Keep every catalog entry in one of these user-facing domains:

1. `Wi‑Fi`
2. `网络诊断`
3. `流量与性能`
4. `远程与服务`
5. `IP 与寻址`
6. `API 与协议`
7. `数据与转换`
8. `安全与标识`
9. `后端工程`

Update the catalog, category translation switch, category colors and desktop sidebar together.
Every entry needs English discovery copy in `tool_strings_*_en.dart`.

## Dedicated workbenches

- Timestamp: IANA time zones, seconds/milliseconds/microseconds/nanoseconds, RFC 3339, batch input,
  time differences and language snippets.
- Regex: presets, capture groups, replacement preview, syntax explanation, risk hints and flavor
  compatibility. Dart `RegExp` is the execution engine; never claim another engine was executed.
- JSON/data: formatting, recursive key sorting, JSONPath, JSON/YAML/CSV conversion, semantic diff,
  practical JSON Schema checks and model generation.
- JWT: decode, claim inspection, expiry/security warnings and HS256/384/512 verification/signing.
  Secrets stay in memory and never enter tool drafts.
- Cron: five-field POSIX/Vixie semantics, macros, explanation, warnings and upcoming run times.
- Backend: SQL helpers, UUID/ULID/ObjectId/Snowflake inspection, SemVer precedence, HTTP metadata and
  mixed text/JSON-line log inspection.

Keep pure behavior in the corresponding service and page interaction in the corresponding page.
Add or extend `test/professional_developer_tools_test.dart` for parsing and boundary behavior.

## Draft and localization contract

Use `ToolDraftRepository` for non-sensitive input, selected tabs, filters and display options. Restore
parameters, never restart a task. Reset must remove the stored scope. Do not add secrets to a payload
even though the repository has a defensive sanitizer.

Every `LocalizedText` and `context.tr` source needs an English mapping. Dynamic result models should
prefer stable fields rendered through localized labels rather than concatenated translated prose.
Run the localization test after adding a page and update generated documentation goldens only when
the visual change is intentional.
