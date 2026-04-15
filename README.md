# Prickles

A tiny unofficial status indicator for Claude (Anthropic's AI assistant), featuring **Claudia the hedgehog**. Live at **[jessica-he.com/prickles](https://jessica-he.com/prickles)**.

Claudia has three moods:

| Mood | When |
|---|---|
| 🦔 Good (normal) | Claude is operating normally. |
| 🦔 Confused | Rumblings on Reddit but Anthropic hasn't declared an incident. |
| 🦔 Rough time | Anthropic has an active incident affecting Claude. |

## How it works

A GitHub Action runs every 5 minutes and executes [`scripts/update.py`](scripts/update.py), which:

1. Fetches [Anthropic's official status page](https://status.anthropic.com/api/v2/summary.json). Any Claude-affecting incident → **Error** state.
2. If Anthropic is clean, checks [r/ClaudeAI](https://reddit.com/r/ClaudeAI) and [r/Anthropic](https://reddit.com/r/Anthropic) for the most recent post matching outage-related keywords in the last hour. Fetches that post's comments and counts how many comments also match keywords. If 3+ matching comments → **Confused** state.
3. Writes the result to [`docs/status.json`](docs/status.json) and, on state changes, appends a history entry to [`docs/history.json`](docs/history.json) (capped at 10 entries).
4. Commits and pushes the updated JSON files back to this repo.

GitHub Pages serves [`docs/`](docs/) at `jessica-he.com/prickles`. The webpage reads `status.json` client-side and renders the current Claudia face.

### State transition rules

- **Error** is set only by Anthropic's status page, and cleared only by Anthropic (Reddit signals are ignored during recovery — Reddit always lags reality).
- **Confused → Good** requires a 15-minute cooldown to prevent the face from flickering during borderline activity.
- **Good → anything** applies immediately.

## Architecture

```
jesshe21/prickles/                  (this repo)
├── .github/workflows/update.yml   — cron every 5 min
├── scripts/update.py              — the status checker (stdlib only)
├── docs/                          — served at jessica-he.com/prickles
│   ├── index.html
│   ├── privacy.html
│   ├── terms.html
│   ├── status.json                — auto-updated
│   ├── history.json               — auto-updated
│   └── assets/                    — Claudia PNGs
└── ios/                           — Xcode project (coming soon)
```

Everything runs on **GitHub Actions + GitHub Pages**. No servers, no databases, no secrets, no monthly bill.

## Running the updater locally

```bash
python3 scripts/update.py
```

It writes `docs/status.json` and `docs/history.json` in place. Uses only Python's standard library — no `pip install` required. Works on any Python 3.9+.

## Security posture

This repo is fully public and intentionally contains no secrets:

- Anthropic's status API is public and requires no auth.
- Reddit's public JSON endpoints require no auth, just a `User-Agent` header (set in `update.py`).
- The GitHub Action uses the auto-injected `GITHUB_TOKEN` (never committed).
- The widget collects no user data. No analytics, no telemetry.

If you think you've found a vulnerability, please email the maintainer directly rather than opening a public issue.

## Not affiliated with Anthropic

Prickles is an unofficial community project. It is not affiliated with, endorsed by, or connected to Anthropic PBC. Claude and related marks are trademarks of Anthropic. For authoritative status information, please consult [status.anthropic.com](https://status.anthropic.com).

## License

MIT. See [LICENSE](LICENSE).
