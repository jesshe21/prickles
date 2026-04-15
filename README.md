# Prickles

A tiny unofficial status indicator for Claude (Anthropic's AI assistant), featuring **Prickles the hedgehog**. Live at **[jessica-he.com/prickles](https://jessica-he.com/prickles)**.

Prickles has two moods:

| Mood | When |
|---|---|
| 🦔 Feeling great | Claude is operating normally. |
| 🦔 Has DIED | Anthropic has an active incident affecting Claude, OR a Claude component is degraded. |

## How it works

A GitHub Action runs every 5 minutes and executes [`scripts/update.py`](scripts/update.py), which:

1. Fetches [Anthropic's official status page](https://status.anthropic.com/api/v2/summary.json).
2. If any Claude-affecting incident is active (`investigating`, `identified`, or `monitoring`), OR any component with "claude" in its name is in a non-operational state → **error**. Otherwise → **good**.
3. Writes the result to [`docs/status.json`](docs/status.json) and, on state changes, appends an entry to [`docs/history.json`](docs/history.json) (capped at 10 entries).
4. Commits and pushes the updated JSON files back to this repo.

GitHub Pages serves [`docs/`](docs/) at `jessica-he.com/prickles`. The webpage reads `status.json` client-side and renders the current Prickles face inside a tilted polaroid frame.

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
│   └── assets/                    — Prickles PNGs
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

- Anthropic's status API is public and requires no auth — it's the only network dependency.
- The GitHub Action uses the auto-injected `GITHUB_TOKEN` (never committed).
- The webpage and widget collect no user data. No analytics, no telemetry.

If you think you've found a vulnerability, please email the maintainer directly rather than opening a public issue.

## Not affiliated with Anthropic

Prickles is an unofficial community project. It is not affiliated with, endorsed by, or connected to Anthropic PBC. Claude and related marks are trademarks of Anthropic. For authoritative status information, please consult [status.anthropic.com](https://status.anthropic.com).

## License

MIT. See [LICENSE](LICENSE).
