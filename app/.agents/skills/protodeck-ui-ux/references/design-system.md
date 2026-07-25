# ProtoDeck design system

## Product character

Aim for a calm professional control surface with strong hierarchy, generous whitespace, direct status
and the information density needed by a network engineer. The visual language must stand on its own;
do not describe or implement it as an imitation of another product.

## Foundation

The current Material 3 seed/primary is cobalt blue around `#3578F6`, with sky blue secondary around
`#42B6E9`. Preserve a bright light theme:

- App/background: cool near-white, not mid-gray.
- Primary cards: white with subtle cool outline/shadow.
- Primary tint: pale blue for selection and low-emphasis status.
- Text: deep blue-black for primary, cool gray for secondary.
- Status: green only for verified success, amber for partial/warning, red for verified failure.

Centralize reusable decisions in `lib/app.dart` theme or shared widgets. Do not scatter slightly
different blues, radii and shadows through new pages.

## Spatial hierarchy

- Screen horizontal padding: generally 16 dp on phones, 20–24 dp on wider layouts.
- Related-control gap: 8–12 dp; separate-card/section gap: 16–20 dp.
- Primary cards: approximately 20–24 dp radius. Small controls/chips: approximately 12–16 dp.
- Prefer one hero/status surface, one compact action row and clearly separated supporting sections.
- Avoid a card around every value. Use a compact 2–3 column metric grid inside one coherent surface.
- Keep connection-method icons left-aligned with their label/value rather than floating decoratively.

## Type and controls

- Page/product title: strong 24–30 sp where space permits; page title around 20–24 sp.
- Section heading: 15–17 sp semibold/bold. Body: 14–16 sp. Supporting text: 12–13 sp with sufficient
  contrast; do not fill screens with faint captions.
- Primary action height: at least 48 dp, visually filled and labeled. Secondary action is outlined or
  tonal. Use an icon-only action only for universally recognized secondary operations.
- Presets such as Public DNS/Baidu/Cloudflare must look like chips/buttons, including selected/pressed
  state, padding and bounded hit area.

## Page patterns

### Home

Lead with internet/connection state, network name and the most important signal/quality visualization.
Compress interface, local IP, gateway and DNS into small metrics or an expandable detail. Place one-tap
diagnosis in a visually compatible action area rather than an unrelated saturated block.

### Wi-Fi

Use top tabs/header sections for Current, Nearby and Channel Analysis. Nearby needs search, band filter,
sort, signal glyph plus dBm and tappable detail rows. Current needs the live chart, timestamp/cadence and
technical details after the status hierarchy.

### Ping and diagnostic tools

Initially show protocol, target, obvious presets and Start. Keep advanced count/continuous/interval/
timeout/size/family in a clearly tappable section. Once running, prioritize live status, chart, summary
metrics and Stop; raw output can be lower/expandable.

### Stateful workbenches

REST/API and remote tools use a stable command/input area plus a resizable or tabbed response/log area.
Connect, subscribe and send controls must be visually distinct and state-aware. Received messages need
direction/topic/type/timestamp cues and JSON formatting without hiding raw content.

### Files

Phone portrait switches Local/Remote or Terminal/Files; landscape/tablet may use two panes. A sortable
header looks interactive, shows ▲/▼ and keeps current path/back/up controls reachable.

## Charts

- Always reserve a finite height and verify parent constraints.
- Ensure axis range remains nonzero for a single/repeated value.
- Wi-Fi: `minY=-100`, `maxY=0`; top means stronger. Use subtle horizontal grid lines and meaningful
  labels, not a line drawn against an accidentally inverted scale.
- Ping: `minY=0`, dynamic padded `maxY`; represent timeout as a gap/marker, not zero latency.
- Limit retained/displayed samples or downsample for long sessions. Do not rebuild the entire page for
  every high-frequency event.

## Accessibility and responsiveness

- Minimum touch target 48×48 dp and readable color contrast.
- Do not encode status by color alone; pair icon/text/shape.
- Test text scale at least 1.3 and avoid fixed heights around multiline labels.
- Respect SafeArea, keyboard insets and scrollability. Keep the active text editor and primary action
  visible when the keyboard opens.
