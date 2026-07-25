---
name: protodeck-ui-ux
description: ProtoDeck mobile product UI and interaction system for modern Material 3 layouts, bright sky-blue visual hierarchy, calm device-control dashboard styling, responsive phone/tablet behavior, touch affordance, forms, live consoles, charts and truthful success/warning/error states. Use for any user-visible Flutter page or widget change, especially Home, Wi-Fi, Ping, diagnosis, tool grids, SSH/files, API/MQTT/Bluetooth workbenches and data visualizations.
---

# ProtoDeck UI UX

Read [design-system.md](references/design-system.md) before creating a new page pattern or changing
theme, spacing, card hierarchy, status semantics or charts.

## Design from the user journey

1. Identify the page's primary job and the one action/result that must be visible first.
2. Group secondary parameters behind a clearly tappable disclosure, tabs or an advanced section.
3. Separate input, run controls, live status and results. Keep stop reachable without causing layout
   jumps when a task starts.
4. Design empty, loading, partial, permission-required, unsupported, success, warning, failure and
   cancelled states before polishing the happy path.
5. Preserve the user's entered values and useful partial results across errors/retries.

## Make interaction obvious

- Use Material buttons, InkWell/InkResponse, ListTile, FilterChip/ChoiceChip or another visible control.
  Do not present bare gray text as a tappable preset.
- Give icon-only actions a tooltip/semantic label and a minimum 48×48 logical-pixel touch target.
- Use icon plus text for important connect/start/subscribe/send/file actions. Disabled controls must
  explain prerequisite state nearby.
- Provide pressed/selected/focus feedback. Keep destructive actions visually and spatially distinct.
- Avoid dense nested cards and borderless groups. Maintain visible gaps and one clear surface hierarchy.

## Apply the visual direction

- Use bright near-white surfaces with restrained sky/cobalt blue as the primary accent. Gray is for
  secondary text, not the dominant page atmosphere.
- Prefer typography, whitespace and alignment over decorative gradients. Reserve semantic green,
  amber and red for verified status.
- Keep the four primary destinations Home, Wi-Fi, Tools and Remote. Settings belongs in the Home gear;
  do not reintroduce History navigation.
- On compact phones use single-column progressive disclosure. At ≥720 dp use adaptive rail/two-pane
  layouts only when they improve task continuity.
- Keep values/addresses/logs in readable monospaced styling where alignment matters; keep prose in the
  platform UI font.

## Present status truthfully

- Never leave a container green when a required child diagnostic failed. Aggregate border/icon/text
  all derive from the latest result set.
- Show unavailable/unknown/cached separately from failure. Avoid a green check for “not tested”.
- Signal cards may change tint by evidence-based quality, but retain accessible contrast and include
  the numeric metric.
- Public-IP absence is a small secondary state, not a dominant offline error.

## Build robust visualizations

- Handle zero points, one point, repeated values, null gaps and long series explicitly.
- Wi-Fi signal charts use a fixed `-100..0 dBm` domain with readable labels and a foreground sample
  cadence such as two seconds. The Home signal chart belongs in the primary network card.
- Ping latency charts start at zero and choose a padded upper bound; show loss and min/avg/max/jitter
  next to the chart without covering it.
- Wi-Fi channel views label visible channel numbers rather than only MHz. Provide both occupancy bars
  and frequency/channel-width strength envelopes, with band filters and current AP emphasis.
- Traceroute maps preserve hop order and use subtle lines, small nodes and label collision handling.

## Verify usability

Add focused widget tests for tap targets, collapsed/expanded sections, loading/failed status and chart
presence. Inspect at a narrow phone size, large font/text scale, dark theme and a ≥720 dp layout. Use a
real device for keyboard, safe area, scrolling, permission sheets and sustained live updates.
