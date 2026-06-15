#!/usr/bin/env python3
"""Prickles status updater.

Determines Claude's current status by checking Anthropic's official
status page. Two states only: good or error.

Writes docs/status.json every run. On state changes, appends to
docs/history.json (trimmed to the most recent entries).

Runs on a GitHub Actions cron every 5 minutes. See
.github/workflows/update.yml.
"""
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

USER_AGENT = "Prickles/1.0 (+https://jessica-he.com/prickles)"
ANTHROPIC_STATUS_URL = "https://status.claude.com/api/v2/summary.json"

REPO_ROOT = Path(__file__).resolve().parent.parent
DOCS = REPO_ROOT / "docs"
STATUS_FILE = DOCS / "status.json"
HISTORY_FILE = DOCS / "history.json"

HTTP_TIMEOUT_SECONDS = 15
HISTORY_MAX_ENTRIES = 10

# Incident statuses that mean an incident is currently open (not resolved).
# Used only to surface the incident's name/link in status.json — NOT to decide
# whether Prickles is down. resolved and postmortem mean "it's over".
ACTIVE_INCIDENT_STATUSES = ("investigating", "identified", "monitoring")

# Anthropic's overall indicator value meaning "All Systems Operational".
INDICATOR_OK = "none"


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


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


def classify(data):
    """Pure decision: given an Anthropic summary.json payload, return
    (is_error, info_dict).

    Prickles mirrors Anthropic's own headline. It is an error iff Anthropic's
    overall indicator is anything but "none" (All Systems Operational), OR a
    core Claude component is non-operational. A deliberate, narrow model
    suspension (e.g. retiring Mythos/Fable) keeps the indicator at "none", so
    Prickles stays happy even though an incident is technically open.

    Any open incident's name/link is still captured in info for transparency,
    regardless of whether we consider it an outage.
    """
    indicator = (data.get("status") or {}).get("indicator") or INDICATOR_OK

    claude_components_degraded = [
        c.get("name") for c in data.get("components", [])
        if "claude" in (c.get("name") or "").lower()
        and c.get("status") not in (None, "operational")
    ]

    active_incidents = [
        inc for inc in data.get("incidents", [])
        if inc.get("status") in ACTIVE_INCIDENT_STATUSES
    ]
    first_incident = active_incidents[0] if active_incidents else None

    is_error = indicator != INDICATOR_OK or bool(claude_components_degraded)

    if first_incident or claude_components_degraded:
        active_incident = {
            "id": first_incident.get("id") if first_incident else None,
            "name": first_incident.get("name") if first_incident else None,
            "url": first_incident.get("shortlink") if first_incident else None,
            "components_degraded": claude_components_degraded,
        }
    else:
        active_incident = None

    info = {
        "status": "operational" if indicator == INDICATOR_OK else indicator,
        "indicator": indicator,
        "active_incident": active_incident,
    }
    return is_error, info


def check_anthropic_status():
    """Fetch Anthropic's status page and classify it. Returns (is_error, info).

    On fetch failure we fail open (not an error) — a flaky network shouldn't
    kill Prickles. The classification itself lives in classify() so it can be
    tested without the network.
    """
    try:
        data = http_get_json(ANTHROPIC_STATUS_URL)
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, ValueError) as e:
        print(f"[anthropic] fetch failed: {e}", file=sys.stderr)
        return False, {"status": "unknown", "indicator": "unknown",
                       "active_incident": None, "error": str(e)}

    return classify(data)


def main() -> int:
    is_error, anthropic_info = check_anthropic_status()

    previous = read_json_file(STATUS_FILE, {})
    prev_state = previous.get("state") if previous else None
    new_state = "error" if is_error else "good"

    now_iso = iso_now()
    state_since = now_iso if new_state != prev_state else previous.get("state_since", now_iso)

    status = {
        "state": new_state,
        "state_since": state_since,
        "last_checked": now_iso,
        "sources": {
            "anthropic": anthropic_info,
        },
        "schema_version": 1,
    }
    write_json_file(STATUS_FILE, status)

    if new_state != prev_state:
        history = read_json_file(HISTORY_FILE, {"entries": [], "schema_version": 1})
        entries = history.get("entries", [])
        if entries and entries[0].get("to") is None:
            entries[0]["to"] = now_iso
        if new_state == "error":
            degraded = (anthropic_info.get("active_incident") or {}).get("components_degraded")
            reason = "component_degraded" if degraded else "anthropic_indicator"
        else:
            reason = "operational"
        entries.insert(0, {
            "state": new_state,
            "from": now_iso,
            "to": None,
            "reason": reason,
        })
        history["entries"] = entries[:HISTORY_MAX_ENTRIES]
        write_json_file(HISTORY_FILE, history)
        print(f"[state change] {prev_state} -> {new_state}")

    print(f"state={new_state} anthropic_error={is_error}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
