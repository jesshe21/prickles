# Prickles — Architecture

This document explains how Prickles works end-to-end: the data sources, the update logic, the state model, the webpage, and the deployment pipeline. Anyone cloning this repo should be able to read this file and understand what the system does and why.

For a higher-level "what is this" overview, see [`README.md`](README.md). For notes specifically about building the iOS/Mac widget on top of this data, see [`ios/README.md`](ios/README.md).

## One-line summary

Prickles is a tiny unofficial status indicator for Anthropic's Claude. A GitHub Actions cron polls Claude's official status page (and optionally Reddit) every 5 minutes, writes the current state to a JSON file, commits it back to this repo, and a static webpage served by GitHub Pages renders a cute hedgehog whose mood reflects whatever Claude is going through.

## The three states

Prickles has exactly three possible moods:

| State | Meaning | Trigger |
|---|---|---|
| **good** | Claude is operating normally. | Default when no other condition is met. |
| **confused** | Users on Reddit seem to be hitting issues, but Anthropic hasn't declared an incident yet. Early-warning indicator. | A matching Reddit post from the last hour exists *and* has 3+ comments (also from the last hour) that also match outage keywords. |
| **error** | Anthropic has officially declared a Claude-affecting incident. | Anthropic's status API reports an active incident in one of `investigating`, `identified`, `monitoring`, or any Claude-named component in a non-operational state. |

**Asymmetry is intentional**:
- Only Anthropic can trigger Error. Only Anthropic can clear Error. Reddit signals are ignored during recovery because Reddit always lags reality.
- A 15-minute cooldown prevents Confused → Good transitions when activity briefly dips, to avoid flickering during borderline incidents.

See [`scripts/update.py`](scripts/update.py) function `decide_state()` for the exact transition table.

## Data sources

### 1. Anthropic status API (authoritative)

- URL: `https://status.anthropic.com/api/v2/summary.json`
- Public, no authentication required.
- We look at two fields:
  - `incidents[*].status` — any incident in `investigating`, `identified`, or `monitoring` triggers Error.
  - `components[*]` — any component with `"claude"` in its name whose `status` is not `operational` also triggers Error (catches degraded states even without a declared incident).

### 2. Reddit (early-warning, best-effort)

- URLs: `https://www.reddit.com/r/ClaudeAI/new.json?limit=25` and the same for `r/Anthropic`.
- Public unauthenticated access blocks requests from most cloud IPs (GitHub Actions gets 403'd). **Reddit OAuth is required in production** to bypass this. See [Reddit authentication](#reddit-authentication) below.
- For each subreddit, the script finds the most recent post from the last hour whose title or body matches any outage keyword, then fetches that post's comments and counts how many comments (also from the last hour) match keywords. If any subreddit shows 3+ matching comments on a matching recent post, Confused is triggered.

### Keyword list

Defined in [`scripts/update.py`](scripts/update.py):

```python
KEYWORDS = [
    "down", "broken", "error", "errors", "500", "slow", "overloaded",
    "not working", "capacity", "unavailable", "lagging", "dead",
    "timeout", "timing out", "rate limit",
]
```

Matching is case-insensitive with word boundaries.

## Data flow

```
┌──────────────────────────────────────────────────────┐
│  GitHub Actions cron (.github/workflows/update.yml)  │
│  Triggers every 5 minutes                            │
└─────────────────────┬────────────────────────────────┘
                      │ runs
                      ▼
┌──────────────────────────────────────────────────────┐
│  scripts/update.py                                   │
│                                                      │
│  1. Fetch Anthropic summary.json                     │
│  2. If Anthropic reports incident → state = error    │
│  3. Otherwise fetch Reddit (r/ClaudeAI, r/Anthropic) │
│  4. Keyword-match posts + comments → state decision  │
│  5. Read previous state from docs/status.json        │
│  6. Apply transition rules (cooldown, Anthropic-only │
│     recovery from error)                             │
│  7. Write new state to docs/status.json              │
│  8. If state changed, append to docs/history.json    │
│     (trimmed to last 10 entries)                     │
└─────────────────────┬────────────────────────────────┘
                      │ git commit + git push
                      ▼
┌──────────────────────────────────────────────────────┐
│  docs/status.json and docs/history.json in main      │
└─────────────────────┬────────────────────────────────┘
                      │ GitHub Pages auto-rebuilds /docs
                      ▼
┌──────────────────────────────────────────────────────┐
│  https://jessica-he.com/prickles/                    │
│                                                      │
│  - docs/index.html (webpage, fetches status client-  │
│    side every 60s and on tab focus)                  │
│  - docs/status.json (public JSON, consumed by page   │
│    and future iOS widget)                            │
│  - docs/history.json (last ~10 state changes)        │
└──────────────────────────────────────────────────────┘
```

## API schemas

### `docs/status.json`

```jsonc
{
  "state": "good" | "confused" | "error",
  "state_since": "2026-04-15T17:02:38Z",  // when we entered the current state
  "last_checked": "2026-04-15T18:05:26Z", // when the cron last ran
  "sources": {
    "anthropic": {
      "status": "operational" | "incident" | "degraded" | "unknown",
      "active_incident": null | {
        "id": "f00h6l76tsjs",
        "name": "Elevated errors on Claude.ai, API, Claude Code",
        "url": "https://stspg.io/...",
        "components_degraded": ["claude.ai", "Claude Code"]
      }
    },
    "reddit": {
      "triggered_by": null | {
        "subreddit": "ClaudeAI",
        "post_title": "...",
        "post_url": "https://reddit.com/...",
        "matching_comments": 5
      },
      "skipped_because": null | "error_state"
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
      "reason": "anthropic_incident" | "reddit_rumblings" | "operational"
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
│       ├── normal.png          Good state (happy Claudia)
│       ├── confused.png        Confused state (puzzled Claudia)
│       └── dead.png            Error state (Claudia + ghost)
├── docs/                       Served by GitHub Pages at /prickles
│   ├── .nojekyll               Disables Jekyll processing
│   ├── index.html              The webpage
│   ├── privacy.html
│   ├── terms.html
│   ├── status.json             Current state (auto-updated by cron)
│   ├── history.json            Recent state changes (auto-updated)
│   └── assets/                 Web-optimized 600×600 PNGs
│       ├── good.png
│       ├── confused.png
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

The design uses a dark warm palette with a tilted cream polaroid as the hero element. Fonts: Karla (body), Caveat (polaroid caption), Caprasimo (the "How's Prickles feeling?" question). The polaroid caption itself is state-colored.

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

## Reddit authentication

Reddit blocks unauthenticated API requests from most cloud IP ranges (including GitHub Actions), returning HTTP 403. To get reliable Reddit data in the cron, we use Reddit OAuth in the "client credentials" flow (app-only, no user context needed).

**Credentials are stored as GitHub Actions secrets:**
- `REDDIT_CLIENT_ID`
- `REDDIT_CLIENT_SECRET`

The workflow passes these as environment variables to `update.py`. The script:

1. Reads both env vars at start.
2. If both are set: POST to `https://www.reddit.com/api/v1/access_token` with HTTP Basic auth using the client credentials and `grant_type=client_credentials`. Get back a bearer token. Use `oauth.reddit.com` endpoints with `Authorization: Bearer <token>` on subsequent requests.
3. If either is unset (e.g., running locally on a developer's machine): fall back to unauthenticated `www.reddit.com` endpoints, which work fine from residential IPs.

This means:
- **Production**: authenticated, Reddit works.
- **Local development**: unauthenticated fallback, Reddit still works from a home IP.

Credentials are never committed to the repo. To rotate: regenerate the Reddit app secret at `https://www.reddit.com/prefs/apps` and re-run `gh secret set REDDIT_CLIENT_SECRET --repo jesshe21/prickles`.

## Security posture

This repo is fully public and contains no secrets:
- Anthropic's status API requires no auth.
- Reddit credentials live in GitHub Actions secrets (encrypted at rest, never in the repo source).
- The webpage collects no user data — no analytics, no cookies, no trackers, no third-party scripts beyond Google Fonts.
- The GitHub Action uses the auto-provided `GITHUB_TOKEN`, scoped to this repo only.

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

- **Reddit is blocked from cloud IPs without OAuth.** Handled via credentials (see above).
- **GitHub Actions cron has warm-up and occasional delays.** Not a bug — worst case, the state is 5–15 minutes behind reality. Acceptable for an ambient status indicator.
- **Widget refresh latency on iOS is 15–30 minutes minimum.** Apple's widget refresh budget is out of our control. The webpage refreshes every 60s, the widget less often.
- **Cloudflare + GitHub Pages caching.** The default `Cache-Control: max-age=600` header from GitHub Pages can cause up to 10 minutes of stale JSON at the browser level. The webpage's client-side cache-busting query param mitigates this. For the future iOS widget, the widget's own refresh logic handles staleness via Apple's timeline mechanism.

## Not affiliated with Anthropic

Prickles is an unofficial, community-built status indicator. It is not affiliated with, endorsed by, or connected to Anthropic PBC. Claude and related marks are trademarks of Anthropic. For authoritative status information, please consult [status.anthropic.com](https://status.anthropic.com).
