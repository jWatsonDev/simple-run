# CLAUDE.md — Simple Run

## Memory (openbrain MCP)
At the start of every session, call `get_context` with project "dadhabit" to load relevant context.
When making important decisions (architecture, tech choices, conventions), use `remember` to store them under project "dadhabit".

---

## Project Overview

- **App Name:** Simple Run
- **Concept:** Minimal GPS run tracker — no bloat, just track a run
- **Platform:** iOS (App Store) + Android
- **Stack:** React Native + Expo
- **Goal:** Ship to App Store, learn the submission/approval process
- **Part of:** dadhabit ecosystem (see dadhabit.dad for the bigger vision)

---

## Bigger Vision

Simple Run is a prototype and learning exercise, but it fits into a larger bundled dad lifestyle app concept — combining run tracking, Bible reading (YouVersion API), habit streaks, and family accountability. Think Hallow but for dads.

---

## MVP Feature Set

- GPS tracks a run
- Draws route on a map
- Shows distance / pace / time
- Saves run locally

## Key Packages

- `expo-location` — GPS + background location
- `react-native-maps` — map + route drawing

---

## Setup

```bash
nvm use 20
npx create-expo-app@latest simple-run
cd simple-run
npx expo start
```

---

## Watch Out For

- Apple scrutinizes background location entitlements — requires justification in App Store review
- HealthKit integration (users expect it, add later)
- Battery drain handling

---

## Positioning

"Simple" is the brand. Targeted at users burned by bloated running apps. Keep it minimal — resist feature creep.
