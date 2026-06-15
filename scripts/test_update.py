#!/usr/bin/env python3
"""Tests for the pure status-classification logic in update.py.

No network: classify() takes an already-fetched summary.json payload and
returns (is_error, info). Run with: python3 scripts/test_update.py
"""
import unittest

from update import classify


def summary(indicator="none", incidents=None, components=None):
    """Build a minimal Anthropic summary.json-shaped payload."""
    return {
        "status": {"indicator": indicator, "description": "x"},
        "incidents": incidents or [],
        "components": components or [
            {"name": "claude.ai", "status": "operational"},
            {"name": "Claude API (api.anthropic.com)", "status": "operational"},
        ],
    }


class ClassifyTests(unittest.TestCase):
    def test_narrow_model_suspension_stays_good(self):
        """A minor incident Anthropic keeps green (indicator none) is not an outage."""
        data = summary(
            indicator="none",
            incidents=[{
                "id": "abc",
                "status": "monitoring",
                "impact": "minor",
                "name": "We've suspended access to Claude Mythos 5 and Claude Fable 5",
                "shortlink": "https://stspg.io/abc",
            }],
        )
        is_error, info = classify(data)
        self.assertFalse(is_error)
        # Incident is still captured for transparency even though we're happy.
        self.assertEqual(info["active_incident"]["name"],
                         "We've suspended access to Claude Mythos 5 and Claude Fable 5")

    def test_major_indicator_is_error(self):
        """A real outage raises Anthropic's overall indicator -> DIED."""
        data = summary(
            indicator="major",
            incidents=[{
                "id": "def", "status": "investigating", "impact": "major",
                "name": "Elevated errors on Claude API", "shortlink": "https://stspg.io/def",
            }],
        )
        is_error, info = classify(data)
        self.assertTrue(is_error)
        self.assertEqual(info["indicator"], "major")

    def test_degraded_claude_component_is_error(self):
        """A non-operational core component trips DIED even if indicator is none."""
        data = summary(
            indicator="none",
            components=[
                {"name": "claude.ai", "status": "operational"},
                {"name": "Claude API (api.anthropic.com)", "status": "major_outage"},
            ],
        )
        is_error, info = classify(data)
        self.assertTrue(is_error)
        self.assertIn("Claude API (api.anthropic.com)",
                      info["active_incident"]["components_degraded"])

    def test_all_clear_is_good(self):
        is_error, info = classify(summary())
        self.assertFalse(is_error)
        self.assertEqual(info["status"], "operational")
        self.assertIsNone(info["active_incident"])


if __name__ == "__main__":
    unittest.main()
