# Prickles — Architecture

This document explains how Prickles works end-to-end: the data source, the update logic, the state model, the webpage, and the deployment pipeline. Anyone cloning this repo should be able to read this file and understand what the system does and why.

For a higher-level "what is this" overview, see [`README.md`](README.md). For notes specifically about building the iOS/Mac widget on top of this data, see [`ios/README.md`](ios/README.md).

## One-line summary

Prickles is a tiny unofficial status indicator for Anthropic's Claude. A GitHub Actions cron polls Claude's official status page every 5 minutes, writes the current state to a JSON file, commits it back to this repo, and a static webpage served by GitHub Pages renders a cute hedgehog — **Prickles** — whose mood reflects whatever Claude is going through.

## The two states

Prickles has exactly two moods:

| State | Meaning | Webpage caption examples |
|---|---|---|
| **good** | Claude is operating normally — no active incidents, no degraded components. | "feeling great!", "vibing", "no notes", "claude is up, i am up" |
| **error** | Anthropic has officially declared a Claude-affecting incident, or a Claude component is in a non-operational state. | "Prickles has DIED", "RIP Prickles (again)", "Prickles has fainted", "It's joever" |

That's it. Two states. Transitions are immediate in both directions. No middle state, no cooldown, no tunable thresholds — just "is Anthropic reporting something wrong" or not.

The specific captions shown to visitors are picked at random from a pool defined in `docs/index.html`. On every fresh page load, the visitor sees a slightly different Prickles. Edit the arrays in `index.html` to add, remove, or tweak copy anytime — the site picks from whatever is in the pool.

## Data source

### Anthropic status API (authoritative and only)

- URL: `https://status.anthropic.com/api/v2/summary.json`
- Public, no authentication required.
- We look at two fields:
  - `incidents[*].status` — any incident whose status is `investigating`, `identified`, or `monitoring` triggers error.
  - `components[*]` — any component with `"claude"` in its name whose `status` is not `operational` also triggers error (catches degraded states even without a declared incident).

If neither of those conditions holds, Prickles is in the good state.

**There is no secondary signal.** Earlier designs considered Reddit, Hacker News, and an API canary probe as leading indicators, but each brought meaningful downsides (Reddit's new Responsible Builder Policy, paywalled X API, weak canary signal, etc.). In practice Anthropic declares real incidents within a few minutes of them starting, and running the whole system off one authoritative source keeps it simple, reliable, and dependency-free.

## Data flow

```
┌──────────────────────────────────────────────────────┐
│  GitHub Actions cron (.github/workflows/update.yml)  │
│  Triggers every 5 minutes                            │
└─────────────────────┬────────────────────────────────┘
                      │ runs
                      ▼
┌──────────────────────────────────────────────────────┐
│  scripts/update.py (Python stdlib only)              │
│                                                      │
│  1. Fetch Anthropic summary.json                     │
│  2. Decide state:                                    │
│       error if any active incident or degraded       │
│       Claude component; otherwise good               │
│  3. Read previous state from docs/status.json        │
│  4. Write new state to docs/status.json              │
│  5. If state changed, append entry to                │
│     docs/history.json (trimmed to last 10)           │
└─────────────────────┬────────────────────────────────┘
                      │ git commit + git push
                      ▼
┌──────────────────────────────────────────────────────┐
│  docs/status.json and docs/history.json on main      │
└─────────────────────┬────────────────────────────────┘
                      │ GitHub Pages auto-rebuilds /docs
                      ▼
┌──────────────────────────────────────────────────────┐
│  https://jessica-he.com/prickles/                    │
│                                                      │
│  - docs/index.html (webpage, fetches status every    │
│    60s and on tab focus, picks random caption from   │
│    state pools on state change)                      │
│  - docs/status.json (public JSON, consumed by page   │
│    and future iOS widget)                            │
│  - docs/history.json (last ~10 state changes)        │
└──────────────────────────────────────────────────────┘
```

## API schemas

### `docs/status.json`

```jsonc
{
  "state": "good" | "error",
  "state_since": "2026-04-15T17:02:38Z",  // when we entered the current state
  "last_checked": "2026-04-15T18:34:56Z", // when the cron last ran
  "sources": {
    "anthropic": {
      "status": "operational" | "incident" | "degraded" | "unknown",
      "active_incident": null | {
        "id": "f00h6l76tsjs",
        "name": "Elevated errors on Claude.ai, API, Claude Code",
        "url": "https://stspg.io/...",
        "components_degraded": ["claude.ai", "Claude Code"]
      }
    }
  },
  "schema_version": 1
}
```

### `docs/history.json`

```jsonc
{
  "entries": [
    {
      "state": "error",
      "from": "2026-04-15T17:02:38Z",
      "to": "2026-04-15T18:05:26Z",  // null if this state is currently active
      "reason": "anthropic_incident" | "operational"
    }
    // up to 10 entries, newest first
  ],
  "schema_version": 1
}
```

History is append-prepend: on state changes, the previous entry's `to` is set to the current time, and a new entry is prepended with `to: null`. The list is trimmed to the 10 most recent entries after each insert.

## Repository layout

```
prickles/
├── .github/
│   └── workflows/
│       └── update.yml          GitHub Actions cron (every 5 min)
├── assets/
│   └── icons/                  Original 1024×1024 hedgehog PNGs
│       ├── normal.png          good state
│       ├── dead.png            error state
│       └── confused.png        (unused — kept as archived art)
├── docs/                       Served by GitHub Pages at /prickles
│   ├── .nojekyll               Disables Jekyll processing
│   ├── index.html              The webpage
│   ├── privacy.html
│   ├── terms.html
│   ├── status.json             Current state (auto-updated by cron)
│   ├── history.json            Recent state changes (auto-updated)
│   └── assets/                 Web-optimized 600×600 PNGs
│       ├── good.png
│       └── error.png
├── ios/                        iOS/Mac Xcode project (to be built)
├── scripts/
│   └── update.py               The status checker (Python stdlib only)
├── .gitignore
├── LICENSE                     MIT
├── README.md                   User-facing overview
└── ARCHITECTURE.md             This file
```

## Webpage architecture

The webpage at `docs/index.html` is a single static file with inline CSS and JS — no build step, no framework, no npm. Its job is simple:

1. On load, immediately fetch `status.json` and `history.json` (via a `<link rel="preload">` hint so fetching starts before JS parses).
2. Render the current state: swap the hedgehog image, set the caption inside the polaroid, set the detail line, populate the timeline from history.
3. Re-fetch every 60 seconds via `setInterval`, and also on `visibilitychange` when the tab becomes visible again.
4. All fetches use a minute-granularity cache-busting query param so repeated views within the same minute don't hammer the network but subsequent minutes always get fresh data.

### Copy & image rotation

Each state has **pools** of captions, detail lines, and images, defined near the top of the `<script>` block in `index.html`:

```js
const STATE_META = {
  good: {
    captions: [ "feeling great!", "vibing", "top of the world", ... ],
    details:  [ "Claude is chilling. No complaints.", ... ],
    images:   [ "assets/good.png" ],
  },
  error: {
    captions: [ "Prickles has DIED", "RIP Prickles (again)", ... ],
    details:  [ "Claude is having a real incident.", ... ],
    images:   [ "assets/error.png" ],
  },
};
```

On every page load, the webpage picks one random caption, detail, and image from the relevant pool and renders it. The pick does **not** change on the same page during 60-second `setInterval` refreshes — it only re-rolls when the state itself changes (e.g., good → error → good would pick fresh copy on each transition). This keeps the experience visually stable between automatic refreshes but gives every page load its own little personality.

To add new variants, just edit the arrays in `index.html` and ship. No build step, no schema migration. To add new images, drop the PNG into `docs/assets/` and add the filename to the appropriate `images` array.

### Design notes

The webpage uses a dark warm palette with a tilted cream polaroid as the hero element. Fonts: Karla (body), Caveat (polaroid caption), Caprasimo (the "How's Prickles feeling?" question). The polaroid caption is state-colored (muted green for good, brick red for error).

## Deployment

### GitHub Pages config

- **Branch**: `main`
- **Path**: `/docs`
- **Custom domain**: inherited from the user site `jesshe21.github.io` → `jessica-he.com`, so this project repo is automatically served at `jessica-he.com/prickles/`.
- **HTTPS**: Cloudflare sits in front of GitHub Pages and provides the SSL certificate. GitHub's own "Enforce HTTPS" toggle is unavailable because of this (that's expected, not a bug). Cloudflare has "Always Use HTTPS" enabled separately.

### GitHub Actions workflow

[`update.yml`](.github/workflows/update.yml) runs on:
- `schedule: "*/5 * * * *"` — every 5 minutes
- `workflow_dispatch` — manual trigger via `gh workflow run update.yml`

Permissions: `contents: write` (to commit the updated JSON files back to the repo using the auto-provided `GITHUB_TOKEN`).

**Known GitHub quirks**:
- Scheduled workflows on brand-new public repos have a *warm-up delay* of 30–60 minutes before the cron starts firing reliably. After the initial warm-up, runs generally happen on schedule (though GitHub can delay scheduled runs during high load).
- Scheduled workflows are auto-disabled after 60 days of no repository activity. Since every cron run commits the updated `status.json`, the repo has continuous activity and this never triggers.

## Security posture

This repo is fully public and contains no secrets:
- Anthropic's status API requires no authentication.
- The webpage collects no user data — no analytics, no cookies, no trackers, no third-party scripts beyond Google Fonts.
- The GitHub Action uses the auto-provided `GITHUB_TOKEN`, scoped to this repo only.
- **No API keys, no OAuth, no secrets of any kind are stored anywhere** in this repo or in GitHub Actions secrets. There is genuinely nothing to leak.

See [`docs/privacy.html`](docs/privacy.html) for the user-facing privacy policy.

## Running locally

Requires Python 3.9+ (no pip install needed — stdlib only).

```bash
python3 scripts/update.py
```

This writes `docs/status.json` and `docs/history.json` in place. To preview the webpage:

```bash
cd docs && python3 -m http.server 8765
# then open http://localhost:8765/
```

## Known limitations

- **GitHub Actions cron has warm-up and occasional delays.** Not a bug — worst case, the state is 5–15 minutes behind reality. Acceptable for an ambient status indicator.
- **Lag behind real incidents.** The only signal source is Anthropic's official status page, which has *human* latency (someone has to declare the incident). Prickles will show "good" during the first few minutes of a real outage, until Anthropic pushes the status update. This is a deliberate tradeoff for simplicity and reliability over early warning.
- **Widget refresh latency on iOS will be 15–30 minutes minimum** (once built). Apple's widget refresh budget is out of our control. The webpage refreshes every 60s; the widget will refresh less often.
- **Cloudflare + GitHub Pages caching.** The default `Cache-Control: max-age=600` header from GitHub Pages can cause up to 10 minutes of stale JSON at the browser level. The webpage's client-side cache-busting query param mitigates this.

## Not affiliated with Anthropic

Prickles is an unofficial, community-built status indicator. It is not affiliated with, endorsed by, or connected to Anthropic PBC. Claude and related marks are trademarks of Anthropic. For authoritative status information, please consult [status.anthropic.com](https://status.anthropic.com).
