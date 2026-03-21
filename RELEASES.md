# Ruck & Run — Release History

## Build 3 — v1.0.0 (2026-03-21)
**Status:** Archiving / Submitting to TestFlight

### What's in this build
- GPS run tracking (Run, Ruck, Walk)
- Background location tracking — GPS continues when screen is locked
- Persistent notification showing distance · time · pace (silent, no buzz)
- Route map with polyline — fits full route on finish
- Elevation and pace charts on run detail screen
- Share card — dark card with route map and stats, opens iOS share sheet
- Run history with tappable detail screen
- Effort score based on perceived exertion, pace, elevation, ruck weight
- Ruck weight keyboard fix — Done button dismisses keyboard
- Map no longer defaults to San Francisco

### Known gaps / next up
- HealthKit save workout (deferred — revisit in native Swift rewrite)
- Heart rate from Apple Watch (deferred — needs Watch companion app or native HK)
- Live Activities / Dynamic Island (requires native Swift)

---

## Build 2 — v1.0.0
**Status:** Superseded

- EAS production build (used 1 of free tier credits)
- Background tracking and notification had buzzing bug
- HealthKit integration not working

---

## Build 1 — v1.0.0
**Status:** Superseded

- EAS development build (wasted — should have used production)

---

## Archive command
```bash
xcodebuild -workspace ios/RuckRun.xcworkspace \
  -scheme RuckRun \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath build/RuckRun.xcarchive \
  MARKETING_VERSION=1.0.0 \
  CURRENT_PROJECT_VERSION=<build_number> \
  archive
```
