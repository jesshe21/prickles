#!/usr/bin/env python3
"""Prickles status updater.

Determines Claude's current "mood" and writes docs/status.json plus
(on state change) docs/history.json. Runs on a GitHub Actions cron every 5 min.

Sources of truth:
  1. Anthropic's public status page — authoritative for the Error state.
  2. r/ClaudeAI + r/Anthropic — used to detect early rumblings (Confused).

State rules (see spec in README for full details):
  - Error is set iff Anthropic reports a Claude-affecting incident.
  - Confused is set iff a matching post exists in the last hour AND that
    post has 3+ comments (from the last hour) also matching keywords.
  - Error is only cleared by Anthropic (Reddit signals are ignored for recovery).
  - Confused -> Good transitions have a 15-minute cooldown to prevent flicker.
"""
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

USER_AGENT = "Prickles/1.0 (+https://jessica-he.com/prickles)"

REPO_ROOT = Path(__file__).resolve().parent.parent
DOCS = REPO_ROOT / "docs"
STATUS_FILE = DOCS / "status.json"
HISTORY_FILE = DOCS / "history.json"

ANTHROPIC_STATUS_URL = "https://status.anthropic.com/api/v2/summary.json"
SUBREDDITS = ["ClaudeAI", "Anthropic"]
REDDIT_POSTS_URL = "https://www.reddit.com/r/{sub}/new.json?limit=25"
REDDIT_COMMENTS_URL = "https://www.reddit.com{permalink}.json?limit=100&sort=new"

KEYWORDS = [
    "down", "broken", "error", "errors", "500", "slow", "overloaded",
    "not working", "capacity", "unavailable", "lagging", "dead",
    "timeout", "timing out", "rate limit",
]
KEYWORD_PATTERN = re.compile(
    r"\b(" + "|".join(re.escape(k) for k in KEYWORDS) + r")\b",
    re.IGNORECASE,
)

CONFUSED_MIN_MATCHING_COMMENTS = 3
CONFUSED_COOLDOWN_MINUTES = 15
HISTORY_MAX_ENTRIES = 10
HTTP_TIMEOUT_SECONDS = 15


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_iso(s: str) -> datetime:
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s)


def http_get_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_SECONDS) as resp:
        return json.loads(resp.read().decode("utf-8"))


def read_json_file(path: Path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return default


def write_json_file(path: Path, data) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n")


def contains_keyword(text) -> bool:
    if not text:
        return False
    return bool(KEYWORD_PATTERN.search(text))


def check_anthropic_status():
    """Return (is_error, info_dict)."""
    try:
        data = http_get_json(ANTHROPIC_STATUS_URL)
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, ValueError) as e:
        print(f"[anthropic] fetch failed: {e}", file=sys.stderr)
        return False, {"status": "unknown", "active_incident": None, "error": str(e)}

    active_incidents = [
        inc for inc in data.get("incidents", [])
        if inc.get("status") in ("investigating", "identified", "monitoring")
    ]

    claude_components_degraded = [
        c for c in data.get("components", [])
        if "claude" in (c.get("name") or "").lower()
        and c.get("status") not in (None, "operational")
    ]

    if active_incidents or claude_components_degraded:
        first_incident = active_incidents[0] if active_incidents else None
        info = {
            "status": "incident" if active_incidents else "degraded",
            "active_incident": {
                "id": first_incident.get("id") if first_incident else None,
                "name": first_incident.get("name") if first_incident else None,
                "url": first_incident.get("shortlink") if first_incident else None,
                "components_degraded": [c.get("name") for c in claude_components_degraded],
            },
        }
        return True, info

    indicator = (data.get("status") or {}).get("indicator", "none")
    return False, {
        "status": "operational" if indicator == "none" else indicator,
        "active_incident": None,
    }


def count_matching_comments(listing, since: datetime) -> int:
    """Recursively count comments posted since `since` that contain a keyword."""
    if not isinstance(listing, dict):
        return 0
    count = 0
    children = (listing.get("data") or {}).get("children", [])
    for c in children:
        if c.get("kind") != "t1":
            continue
        cd = c.get("data", {}) or {}
        created_ts = cd.get("created_utc")
        if not created_ts:
            continue
        created = datetime.fromtimestamp(created_ts, tz=timezone.utc)
        if created < since:
            continue
        if contains_keyword(cd.get("body", "")):
            count += 1
        replies = cd.get("replies")
        if isinstance(replies, dict):
            count += count_matching_comments(replies, since)
    return count


def check_reddit_rumblings():
    """Return (is_confused, info_dict)."""
    now = datetime.now(timezone.utc)
    hour_ago = now - timedelta(hours=1)

    trigger = None

    for sub in SUBREDDITS:
        try:
            posts_data = http_get_json(REDDIT_POSTS_URL.format(sub=sub))
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, ValueError) as e:
            print(f"[reddit/{sub}] posts fetch failed: {e}", file=sys.stderr)
            continue

        posts = (posts_data.get("data") or {}).get("children", [])
        matching = []
        for p in posts:
            d = p.get("data") or {}
            ts = d.get("created_utc")
            if not ts:
                continue
            created = datetime.fromtimestamp(ts, tz=timezone.utc)
            if created < hour_ago:
                continue
            if contains_keyword(d.get("title", "")) or contains_keyword(d.get("selftext", "")):
                matching.append((created, d))

        if not matching:
            continue

        matching.sort(key=lambda x: x[0], reverse=True)
        _, latest = matching[0]
        permalink = latest.get("permalink")
        if not permalink:
            continue

        try:
            comments_data = http_get_json(REDDIT_COMMENTS_URL.format(permalink=permalink))
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, ValueError) as e:
            print(f"[reddit/{sub}] comments fetch failed: {e}", file=sys.stderr)
            continue

        if not isinstance(comments_data, list) or len(comments_data) < 2:
            continue
        comment_listing = comments_data[1]
        matching_comment_count = count_matching_comments(comment_listing, hour_ago)

        print(
            f"[reddit/{sub}] latest matching post: {latest.get('title')!r} "
            f"— {matching_comment_count} matching comments in last hour",
            file=sys.stderr,
        )

        if matching_comment_count >= CONFUSED_MIN_MATCHING_COMMENTS and trigger is None:
            trigger = {
                "subreddit": sub,
                "post_title": latest.get("title"),
                "post_url": f"https://reddit.com{permalink}",
                "matching_comments": matching_comment_count,
            }

    if trigger:
        return True, {"triggered_by": trigger}
    return False, {"triggered_by": None}


def decide_state(previous: dict, is_error: bool, is_confused: bool, now: datetime) -> str:
    prev = (previous or {}).get("state")

    if is_error:
        return "error"

    if prev == "error":
        return "confused" if is_confused else "good"

    if is_confused:
        return "confused"

    if prev == "confused":
        since_str = (previous or {}).get("state_since")
        if since_str:
            try:
                if now - parse_iso(since_str) < timedelta(minutes=CONFUSED_COOLDOWN_MINUTES):
                    return "confused"
            except ValueError:
                pass
        return "good"

    return "good"


def reason_for(state: str) -> str:
    return {
        "error": "anthropic_incident",
        "confused": "reddit_rumblings",
        "good": "operational",
    }.get(state, "unknown")


def main() -> int:
    now = datetime.now(timezone.utc)

    is_error, anthropic_info = check_anthropic_status()
    if is_error:
        is_confused = False
        reddit_info = {"triggered_by": None, "skipped_because": "error_state"}
    else:
        is_confused, reddit_info = check_reddit_rumblings()

    previous = read_json_file(STATUS_FILE, {})
    new_state = decide_state(previous, is_error, is_confused, now)
    prev_state = previous.get("state") if previous else None

    now_iso = iso_now()
    state_since = now_iso if new_state != prev_state else previous.get("state_since", now_iso)

    status = {
        "state": new_state,
        "state_since": state_since,
        "last_checked": now_iso,
        "sources": {
            "anthropic": anthropic_info,
            "reddit": reddit_info,
        },
        "schema_version": 1,
    }
    write_json_file(STATUS_FILE, status)

    if new_state != prev_state:
        history = read_json_file(HISTORY_FILE, {"entries": [], "schema_version": 1})
        entries = history.get("entries", [])
        if entries and entries[0].get("to") is None:
            entries[0]["to"] = now_iso
        entries.insert(0, {
            "state": new_state,
            "from": now_iso,
            "to": None,
            "reason": reason_for(new_state),
        })
        history["entries"] = entries[:HISTORY_MAX_ENTRIES]
        write_json_file(HISTORY_FILE, history)
        print(f"[state change] {prev_state} -> {new_state}")

    print(f"state={new_state} anthropic_error={is_error} reddit_confused={is_confused}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
