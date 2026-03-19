# Simple Run — MVP

## Core Features

| # | Feature | Description |
|---|---------|-------------|
| 1 | Start / Stop Run | Single button to begin and end a run session |
| 2 | GPS Tracking | Record location points throughout the run |
| 3 | Live Route Map | Draw the route on a map in real time |
| 4 | Live Stats | Distance, pace, elapsed time shown during run |
| 5 | Run Summary | Post-run screen: total distance, avg pace, time, map snapshot |
| 6 | Save Run Locally | Persist run history on device (no account required) |
| 7 | Run History List | View past runs with date, distance, time |

---

## Tech Stack & Costs

| Package / Service | Purpose | Cost |
|-------------------|---------|------|
| Expo (managed workflow) | App framework, build tooling | Free |
| `expo-location` | GPS + background location | Free |
| `react-native-maps` | Map display + route polyline | Free |
| `@react-native-async-storage/async-storage` | Local run storage | Free |
| Expo Go (dev) | Test on device during development | Free |
| EAS Build (production) | Build .ipa / .apk for submission | Free tier: 30 builds/mo |
| Apple Developer Program | App Store submission (iOS) | $99/yr |
| Google Play Developer | App Store submission (Android) | $25 one-time |

**Total to ship MVP: ~$99–$124**

---

## Estimated Timeframe

| Phase | Tasks | Est. Time |
|-------|-------|-----------|
| 1. Scaffold | Expo setup, folder structure, navigation shell | 1–2 hrs |
| 2. GPS + Tracking | expo-location, record coordinates, start/stop logic | 3–4 hrs |
| 3. Map + Route | react-native-maps, draw polyline live | 2–3 hrs |
| 4. Stats Display | Distance calc, pace, timer | 2–3 hrs |
| 5. Run Summary | Post-run screen, data display | 2 hrs |
| 6. Local Storage | Save/load runs with AsyncStorage | 2 hrs |
| 7. History Screen | List past runs | 2 hrs |
| 8. Polish + Testing | UI cleanup, edge cases, device testing | 3–4 hrs |
| 9. Support Site | Enable GitHub Pages on repo, add `docs/index.html` + `docs/privacy.html` | 30–60 min |
| 10. App Store Submission | EAS build, screenshots, metadata, review wait | 3–5 hrs + review (1–7 days) |

**Total dev time: ~21–27 hrs**
**Apple review wait: 1–7 days (typically 1–2)**

---

## App Store URL Requirements

| Field | Required | Solution |
|-------|----------|---------|
| Support URL | Yes | `https://watsonjamd.github.io/simple-run` |
| Privacy Policy URL | Yes | `https://watsonjamd.github.io/simple-run/privacy` |
| Marketing URL | No | Skip for MVP |

> Host via GitHub Pages (`docs/` folder in the repo) — free, no brand association with dadhabit.
