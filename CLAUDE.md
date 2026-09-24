# CLAUDE.md — Ruck & Run (Swift)

## Memory (openbrain MCP)
At the start of every session, call `get_context` with project "dadhabit" to load relevant context.
When making important decisions (architecture, tech choices, conventions), use `remember` to store them under project "dadhabit".

---

## Project Overview

- **App:** Ruck & Run — native Swift/SwiftUI rewrite (working target name: `HybridAthlete`)
- **Concept:** Simple activity tracker (run / ruck / walk) with full HealthKit integration and effort feedback relative to your own baseline
- **Platform:** iOS 17+, iPhone only
- **Goal:** Ship to the App Store
- **Part of:** dadhabit ecosystem (see dadhabit.dad for the bigger vision)
- **Plan / vision:** see `future.md`

The original React Native/Expo app (Build 12, TestFlight) lives on the `rn-archive` branch and the `rn-final` tag. It is not developed further.

---

## Project Layout

- `project.yml` — xcodegen spec (source of truth for the Xcode project)
- `HybridAthlete/` — Swift sources, Info.plist, entitlements
- `docs/` — GitHub Pages support + privacy pages (https://jwatsondev.github.io/simple-run). Don't move or rename; the App Store listing links here. Privacy page must be updated to cover HealthKit data before submission.
- `branding/` — logo and old app icon

## Setup

```bash
brew install xcodegen
xcodegen generate        # after editing project.yml
open HybridAthlete.xcodeproj
```

- Team ID: 6TMKWLMV2K. Bundle ID currently `com.jwatsondev.hybridathlete` (decide before submission: reuse Ruck & Run's `com.jwatsondev.simplerun` / ASC 6760625166, or new listing).

---

## Watch Out For

- Apple scrutinizes background location and HealthKit — usage descriptions and reviewer notes must justify both
- Guideline 4.2 (minimum functionality) — needs real tracking features, not just an HR/HRV readout
- Battery drain handling

---

## Positioning

"Simple" is the brand. Keep it minimal — resist feature creep.
