# Prickles — iOS / iPadOS / macOS Widget

This folder will contain the Xcode project for the Prickles app: a minimal widget-host app with a WidgetKit extension that shows Prickles the hedgehog reacting to Claude's current status.

**This doc exists so that a fresh Claude Code session (or any developer) can pick up the iOS build with zero context and start implementing.** The web side of Prickles is already live at `https://jessica-he.com/prickles/` — the widget just needs to fetch and render the same status data.

For the big-picture architecture of Prickles overall, read [`../ARCHITECTURE.md`](../ARCHITECTURE.md) first.

---

## TL;DR for the next session

Build a Swift + SwiftUI + WidgetKit Xcode project in this folder that:

1. Runs on **iOS 16+ / iPadOS 16+ / macOS 13+** as a single universal target.
2. Provides a **small home screen widget** and a **lock screen widget** that display one of **two** hedgehog poses based on Claude's current status (good or error — no middle state).
3. Fetches `https://jessica-he.com/prickles/status.json` on Apple's widget refresh schedule and renders the state.
4. Ships with a **minimal host app** containing: current status, a scrolling timeline of the last 5 state changes, a link to `status.anthropic.com`, a link to the webpage, and footer with privacy + terms + support.
5. Is submitted to the **App Store** under the name **Prickles** with a short description, the 2 hedgehog assets, a 1024×1024 app icon, and a privacy policy URL.

Everything else in this doc is context to help you build the right thing without having to re-decide anything.

---

## Product decisions (already made, don't re-open)

The web side of Prickles went through a full brainstorming and design session. Those decisions also apply to the widget. Don't revisit them unless the user explicitly asks.

### Character and branding
- **App name**: `Prickles`
- **Character**: a hedgehog named Prickles who reflects Claude's current mood. App name and character name are the same: Prickles. Product copy should talk about "Prickles" the hedgehog.
- **Framing**: the product asks "How's Prickles feeling?" as a playful proxy for "how is Claude doing?"
- **Not affiliated with Anthropic.** Must include a non-affiliation disclaimer in the app and on the App Store listing.

### State model
**Two states**, identical to the web side:
- **good** — Claude is operating normally. Show `normal.png`.
- **error** — Anthropic has declared an incident or a Claude component is degraded. Show `dead.png`.

State logic is handled entirely by the backend cron. The widget never re-computes state — it just reads `state` out of `status.json` and displays the right image + copy.

(An earlier version of the design had a third "confused" state driven by Reddit signals. That was dropped because Reddit's Responsible Builder Policy made the API impractical to use and Anthropic's official status page is a reliable-enough single source of truth. The original `confused.png` art still exists at `../assets/icons/confused.png` as archived art in case a future version wants to revisit a three-state design.)

### Copy for each state (with rotation pools)

The webpage picks random copy from a pool of options on each page load. The widget doesn't have to do the same — on a small home-screen widget there isn't room for caption text anyway, and the iOS app screen can pick one caption per screen open if you want the rotation feel. Here are the full pools used on the web, which should match in the widget's app-screen where space allows:

**good state:**

| Caption pool | Detail pool |
|---|---|
| `feeling great!` | `Claude is chilling. No complaints.` |
| `vibing` | `All quiet on the Anthropic front.` |
| `top of the world` | `No rumblings, no incidents, pure vibes.` |
| `claude is up, i am up` | `Claude seems to be doing Claude things.` |
| `no notes` | `Nothing is on fire for now.` |
| `thriving` |  |
| `everything is fine` |  |
| `chillin hard` |  |
| `all quiet` |  |
| `claude is behaving` |  |

**error state:**

| Caption pool | Detail pool |
|---|---|
| `Prickles has DIED` | `Claude is having a real incident.` |
| `RIP Prickles (again)` | `Anthropic is aware and working on it.` |
| `Prickles is DOWN bad` | `Something is on fire over at Anthropic.` |
| `Prickles has fainted` | `The official status page is screaming.` |
| `Prickles has left the chat` | `The tower is down. Man down. Man down.` |
| `It's joever` |  |
| `Prickles saw God` |  |
| `Prickles is KO'd` |  |
| `Prickles is deceased` |  |
| `Prickles.exe has stopped responding` |  |

For the small home-screen widget (which may only show the hedgehog image with no caption), you don't need copy at all. For the lock-screen widget, one caption from the pool at app-refresh time is fine. For the in-app screen, pick one from each pool on screen open, matching the webpage behavior.

These pools may evolve — the canonical source is the `STATE_META` constant in `docs/index.html`. If you want to sync them at iOS build time, copy from there.

### Visual design (web — reuse where applicable)
- **Palette**: warm dark background (`#1F140C`), cream polaroid surface (`#FFFCF3`), dark brown photo area (`#1D1310`), cream text (`#F7E6C8`), state accents green/orange/red.
- **Hedgehog art**: 1024×1024 PNGs with a dark brown radial vignette *baked into* the image. This means the art looks best inside a dark "frame" (a photo area) rather than floating on a light background.
- **Webpage**: uses a tilted polaroid-style frame for the hedgehog and a handwritten Caveat-font caption beneath it. For the widget, something simpler may be more appropriate — small widgets are small. The key is that the hedgehog art reads clearly at thumbnail size.
- **Fonts used on the webpage**: Caprasimo (question headline), Caveat (polaroid caption), Karla (body). These can inform the widget design but don't need to be exactly replicated — iOS system fonts are fine for the widget.

## Assets

All hedgehog art lives in `../assets/icons/` at **1024×1024 PNG** with the dark warm vignette baked in:

- `../assets/icons/normal.png` → state `good`
- `../assets/icons/dead.png` → state `error`
- `../assets/icons/confused.png` → **currently unused** (kept as archived art in case a future version wants a third state)

For the widget, you may want additional sized variants or a monochrome/tinted version for the iOS 18 lock screen tinted mode. The user (Jess) can provide additional assets on request — she draws the hedgehogs herself.

**Still needed** from the user before App Store submission:
- A 1024×1024 app icon with opaque background (Apple does not allow transparency on app icons). A framed `normal.png` on a solid color square would work.

The web-optimized (600×600) versions at `../docs/assets/` are for the webpage, not the widget. The widget should use the full-resolution originals from `../assets/icons/`.

## Data source

### The endpoint

`https://jessica-he.com/prickles/status.json`

Schema (abbreviated — see [`../ARCHITECTURE.md`](../ARCHITECTURE.md) for the full version):

```jsonc
{
  "state": "good" | "confused" | "error",
  "state_since": "2026-04-15T17:02:38Z",
  "last_checked": "2026-04-15T18:05:26Z",
  "sources": { "anthropic": {...}, "reddit": {...} },
  "schema_version": 1
}
```

### History endpoint (for the in-app timeline)

`https://jessica-he.com/prickles/history.json`

Returns `{ entries: [...], schema_version: 1 }` where entries is an array of state changes, newest first, up to 10 entries. Display only the most recent 5 in the app. `entries[i].to` is `null` for the currently-active state.

### Fetching from Swift

- Use `URLSession.shared` with a plain GET to `https://jessica-he.com/prickles/status.json`. No auth, no headers beyond the default. HTTPS is already set up via Cloudflare.
- Parse with `JSONDecoder` into a `Codable` struct.
- Cache the last successful response in App Group shared storage so both the widget and the host app read the same cache.
- Show a "stale" indicator in the widget UI when the last successful fetch is older than 30 minutes (the webpage does the same).

## Widget target

- Use `WidgetKit` and `AppIntentTimelineProvider` (or `TimelineProvider` if you prefer the older API).
- `TimelineReload.atEnd` with a reasonable refresh cadence (hint 15 min — Apple will throttle as it sees fit).
- Three widget families supported, all sharing the same code:
  - `.systemSmall` (home screen square) — the hero
  - `.accessoryCircular` (lock screen) — tiny circular Prickles
  - `.accessoryRectangular` (lock screen) — with a short caption
- On tap: open the host app.

**Mac support**: no extra work beyond marking the target as universal. The same `.systemSmall` widget shows up in macOS's widget gallery and works on the desktop / Notification Center.

## Host app (minimal)

The Xcode project needs a containing app target because WidgetKit extensions can't be distributed alone — Apple requires an app host. The host app is intentionally minimal but must provide enough "content" to survive App Store review (Guideline 4.2 Minimum Functionality).

### Required screen (just one)

One main screen, scrollable, with:

1. **Current status** — big hedgehog image + state caption + detail line + "last checked X min ago". Mirror the webpage but adapted for native iOS/Mac.
2. **Recent moods** — a list of the last 5 state changes from `history.json`, with state name + start time + duration. Mark the currently-active state with "…and counting" or an "ongoing" indicator so past states and ongoing states are visually distinct.
3. **Link out** — a button that opens `status.anthropic.com` in Safari (iOS) / the default browser (Mac).
4. **Link to webpage** — `jessica-he.com/prickles` (optional, but nice for discoverability).
5. **Footer** — privacy, terms, support. Link out to the webpage's privacy and terms pages (`jessica-he.com/prickles/privacy.html` and `.../terms.html`). Non-affiliation disclaimer: "Prickles is not affiliated with Anthropic. Claude is a trademark of Anthropic."

No settings screen, no login, no preferences, no onboarding, no analytics, no tracking. Keep it one screen.

### App icon

Required for App Store. 1024×1024, opaque. Waiting on user to provide — probably a framed `normal.png` on a solid warm color background.

## App Store submission

### Metadata

- **App name**: Prickles
- **Subtitle**: "Is Claude feeling okay today?"
- **Category**: Utilities
- **Price**: Free
- **Age rating**: 4+
- **Keywords**: claude, anthropic, status, down, widget, ai, monitor
- **Privacy policy URL**: `https://jessica-he.com/prickles/privacy.html` (already live)
- **Support URL**: `https://jessica-he.com/prickles/` (or the privacy page — any live page works)
- **Marketing URL** (optional): `https://jessica-he.com/prickles/`

### Review notes (include in submission)

Short note for Apple's reviewer, roughly:

> Prickles is a community-built, unofficial status indicator for Anthropic's Claude AI assistant. It reads publicly-available information from Anthropic's status page and displays it as a cute hedgehog character. The app is not affiliated with Anthropic. Users who tap the widget are brought to the app's main screen, which shows the current status, recent state changes, and links to Anthropic's official status page.

### Expected review risks

- **4.2 Minimum Functionality**: widget-host apps sometimes get flagged as "repackaged website." Mitigated by including the timeline view, the link to Anthropic's real page, and a useful main screen.
- **5.2 Intellectual Property**: since the app uses "Claude" nominatively (to refer to the actual product it tracks), this should be fine under nominative use. The non-affiliation disclaimer is important. "Prickles" is the app's own name.
- **2.3 Accurate Metadata**: describe the app as unofficial and community-built in the description to avoid confusion.

If the first submission is rejected, iterate on whatever Apple specifies. Don't try to guess ahead.

## Constraints — don't do these

- **No backend of our own.** Everything is static JSON from GitHub Pages. No server to manage.
- **No user data collection.** No analytics, no tracking, no login, no user IDs, no telemetry of any kind. This is a hard rule.
- **No secrets in the app binary.** The widget hits a public URL; there's nothing to embed.
- **No notifications in v1.** It's a deliberate non-goal. Can revisit in v2.
- **No settings screen.** Don't add configurability. Keep it one-hedgehog-one-job.
- **No in-app purchases, no ads, no paid tier.** Free forever.
- **No third-party dependencies beyond what's in iOS SDK.** Pure SwiftUI + WidgetKit + URLSession + JSONDecoder. No CocoaPods, no SPM packages unless absolutely unavoidable.

## Tech stack

- **Language**: Swift 5 (or 6 if Xcode default)
- **UI**: SwiftUI
- **Widget**: WidgetKit with `AppIntentTimelineProvider` (iOS 17+) or `TimelineProvider` (backwards-compat)
- **Networking**: `URLSession` + `JSONDecoder`
- **Local cache**: `UserDefaults(suiteName:)` via App Group, or FileManager in the app group container
- **Target OS**: iOS 16.0+, iPadOS 16.0+, macOS 13.0+
- **Xcode**: 15+
- **No SPM or Cocoapods dependencies.** Stdlib only.

## Workflow for the next session

When you (future Claude) are brought back to continue this work:

1. **Read this file end-to-end.** Also read [`../ARCHITECTURE.md`](../ARCHITECTURE.md) for the data side.
2. **Check `status.json` is live**: `curl https://jessica-he.com/prickles/status.json` should return valid JSON. If not, something about the backend is broken and should be fixed first.
3. **Confirm scope with the user** briefly — Jess is non-technical and trusts the plan, but she might have new ideas or want copy tweaks. Don't rebuild the product from scratch; just confirm "we're building the widget + host app as speced in `ios/README.md`, yeah?" and go.
4. **Scaffold the Xcode project in this folder**. Structure: `Prickles.xcodeproj`, with an app target `Prickles` and a widget extension target `PricklesWidget`. Universal deployment.
5. **Build the widget first**, not the host app. The widget is the hero and the hardest part; the host app is mostly a wrapper.
6. **Test locally on a simulator** before asking Jess to install on her device.
7. **Only once the widget is working end-to-end** should you move to the host app screen.
8. **App Store submission is a separate phase.** Don't jump to it until the widget and app work.

Approximate effort: 4–8 hours of focused work for the widget + minimal app, plus ~1 hour for App Store metadata, plus waiting for Apple review (24–72 hours typically).

## User preferences to know about

Jess is the developer of this project. A few things worth knowing so you collaborate well:

- She is **non-technical**. Explain decisions in plain language. Don't dump Swift syntax in replies unless she asks.
- She **cares deeply about design** and will notice subtle visual tweaks. When presenting visuals, describe them clearly or screenshot what she'd see.
- She **trusts the plan** and doesn't want endless clarifying questions when something is already decided. If in doubt about a decision that was already made, check this file first rather than asking.
- She **prefers to ship fast**. If you can one-shot something that works, do that rather than over-engineering.
- She goes by **Jess**, not Jessica.
- Her email (for App Store support URL fallback) is `jessh1821@gmail.com`.
- Her GitHub account is `jesshe21`.
- Her personal website is `jessica-he.com`.

Good luck, future-you. Prickles is counting on you.
