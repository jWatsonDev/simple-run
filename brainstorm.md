# dadhabit.dad — Run App / App Store Brainstorm

## The Idea

Exploring building a standalone run tracking app as a way to:
1. Learn the App Store submission/approval process
2. Prototype GPS run tracking as a potential feature for a future bundled dad lifestyle app

## Bigger Vision: Bundled Dad Lifestyle App

The long-term concept is a community app specifically for dads that bundles:
- Run tracking (GPS, pace, distance, route)
- Bible reading (YouVersion API integration to avoid licensing headaches)
- Habit streaks
- Family wins / accountability

**Comp:** Hallow proved the bundled model works for a specific identity (Catholics, $70M+ raised). The dad angle is underserved — most fitness/faith apps are gender-neutral or skew female.

**Key insight:** The daily pull is everything. What makes him open it at 5:30am instead of Instagram? That's the feature to nail first.

### Bible Licensing Notes
- KJV: public domain, free JSON datasets on GitHub — fine for a basic app
- NIV: locked down commercially (Zondervan/HarperCollins)
- ESV: free API tier with limits
- Best path: integrate YouVersion API — skip licensing entirely, focus on experience layer

---

## Run App Prototype Plan

**Goal:** Ship something to the App Store to learn the process, not to get rich.

**Stack:** React Native + Expo

**Setup:**
```bash
npx create-expo-app@latest runapp
cd runapp
npx expo start
```

**MVP feature set:**
- GPS tracks a run
- Draws route on a map
- Shows distance / pace / time
- Saves run locally

**Key packages:**
- `expo-location` — GPS + background location (handles a lot of boilerplate)
- `react-native-maps` — map + route drawing

**Watch out for:**
- Apple scrutinizes background location entitlements heavily — requires justification in App Store review
- HealthKit integration (users expect it)
- Battery drain handling

---

## App Name Ideas

| Name | Notes |
|------|-------|
| **Rizen** | Top pick — "risen" + "rise early", faith undertone, works for run app now and bundled app later, unique |
| Stride | Clean, generic, simple |
| DadPace | Dad-specific |
| PaceSetters | Dad-specific |
| Daybreak | Faith + fitness angle |
| FirstLight | Faith + fitness angle |
| Valor | Faith + fitness angle |
| Dad Legs | Lol |
| Running Late | Classic dad joke |

**Favorite: Rizen** — has room to grow into the bigger brand.

---

## Status

- [ ] Create new folder (separate from dadhabit.dad)
- [ ] Scaffold with Expo
- [ ] Add expo-location + react-native-maps
- [ ] Build basic run tracking screen
- [ ] Submit to App Store
