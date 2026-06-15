# Prickles: trust Anthropic's own headline

**Date:** 2026-06-15
**Status:** Approved

## Problem

Prickles shows "🦔 has DIED" whenever Anthropic's status page has *any* active
incident (`investigating` / `identified` / `monitoring`). On 2026-06-15
Anthropic suspended access to two specific legacy models — Claude Mythos 5 and
Claude Fable 5 — and filed an incident for it, even though every Claude
component (`claude.ai`, API, Code, Console, Cowork, Government) stayed
`operational` and Anthropic's own overall headline remained **"All Systems
Operational"** (`indicator: none`).

Result: Prickles reports Claude as down when it isn't. A deliberate, narrow
model suspension is not an outage.

## Key facts about the data source

- Anthropic's status feed (`summary.json`) tracks **systems** as components, not
  individual models. Components are `claude.ai`, `Claude API`, `Claude Code`,
  `Claude Console`, `Claude Cowork`, `Claude for Government`. There is no
  per-model component for Opus / Sonnet / Mythos / Fable.
- Individual models therefore only ever appear in **incident headlines** plus a
  per-incident **severity** (`impact`) and the **overall indicator**
  (`none` / `minor` / `major` / `critical`).
- For the Mythos/Fable suspension, the incident `impact` is `minor` but the
  **overall indicator is `none`** — Anthropic deliberately kept the headline
  green. The overall indicator, not the per-incident impact, is the signal that
  distinguishes "deliberate narrow change" from "real outage."
- `status.anthropic.com/api/v2/summary.json` now 302-redirects to
  `status.claude.com/...`. It still resolves (urllib follows redirects) but the
  canonical URL has moved.

## Decision

Prickles mirrors Anthropic's own assessment instead of tripping on any incident.

**DIED (`is_error = True`) iff:**

```
(overall indicator != "none")  OR  (any core "claude" component is non-operational)
```

The "any active incident → error" rule is removed. Anthropic's overall indicator
becomes the source of truth, with the existing component check kept as a
backstop for the case where a component is degraded without the indicator
catching up.

### Why this matches intent

- "Opus down but Sonnet up — I'm still angry": a real model/infra outage raises
  Anthropic's overall indicator to `minor`/`major`/`critical`, so Prickles DIES.
- "Fable 5 retired — I don't care": Anthropic keeps the indicator at `none`, so
  Prickles stays happy.

We defer the "is this a real problem?" judgment to Anthropic — the authoritative
source — rather than encoding brittle keyword rules ("suspended", "retired").

### Outcomes

| Situation | Indicator | Component state | Prickles |
|---|---|---|---|
| Mythos/Fable suspended (today) | `none` | all operational | happy |
| Real Opus/Sonnet outage | `major`/`critical` | (any) | DIED |
| Core component down | (any) | non-operational | DIED |
| All clear | `none` | all operational | happy |

## Scope of change

Single file: `scripts/update.py`, function `check_anthropic_status()`.

1. Compute `indicator = (data["status"] or {}).get("indicator") or "none"`.
2. Keep `claude_components_degraded` exactly as-is.
3. `is_error = indicator != "none" or bool(claude_components_degraded)`.
4. Still capture the first active incident's name and the indicator into the
   returned `info` dict (for `status.json` transparency) even when `is_error` is
   False. The active-incident block stays under `sources.anthropic`.
5. Update `ANTHROPIC_STATUS_URL` to `https://status.claude.com/api/v2/summary.json`.
6. In `main()`, set the history `reason` to reflect the cause:
   `"component_degraded"` if a component is down, else `"anthropic_indicator"`
   when error, else `"operational"`. Cosmetic but accurate.

### Schema compatibility (no webpage change)

`docs/index.html` reads only:
- `status.state` (`good` / `error`)
- `status.sources.anthropic.active_incident.name` — **only when `state === "error"`**
- history entries' `.state`

The returned `info` keeps `status`, `active_incident` (with `name`), and adds
`indicator`. `state`, `state_since`, `last_checked`, `schema_version` are
unchanged. A benign incident while `state === "good"` is captured but not
displayed (the webpage gates display on the error state). No webpage edits
needed.

## Testing

The repo currently has no tests. Add `scripts/test_update.py` (stdlib
`unittest`, no network — call `check_anthropic_status`-style logic against
in-memory payloads via a small seam, or factor the pure decision into a helper
`classify(data) -> (is_error, info)` and test that).

Cases to pin:
1. Active `minor` incident + `indicator: none` + all components operational
   → **good** (the Mythos/Fable case).
2. `indicator: major` → **error**.
3. A `claude` component non-operational while `indicator: none` → **error**.
4. No incidents, `indicator: none`, all operational → **good**.

Refactor note: extract the pure classification from the network fetch so it is
testable without monkeypatching `urllib`. `check_anthropic_status()` keeps doing
the fetch, then delegates to `classify(data)`.
