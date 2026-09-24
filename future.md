# Future — Phase 2 App

## The Idea

A native Swift/SwiftUI activity tracker for hybrid athletes — rebuild of Ruck & Run with full HealthKit integration and intelligent effort feedback based on personal baselines.

## Who It's For

Hybrid athletes — people who run, ruck, lift, and play sports in the same week. Not beginners. Not pure runners. People who already know what they're doing but want data to validate or challenge their instincts.

## The Core Insight

Most fitness apps compare you to other people or your own PRs. The useful thing is comparing you to *you* — "your HR is higher than normal for this pace today, back off" or "your resting HR is up 4bpm this week, go zone 2 regardless of how you feel."

## The "Execute" Problem

The gap isn't tracking — it's in-the-moment and day-to-day decision making:
- Should I go hard today or easy?
- Am I actually recovering or digging a hole?
- Was today's effort appropriate for where my body is?

Heart rate + HRV trend + resting HR over time can answer these questions. No current app does this well without expensive hardware (Whoop $30/mo) or proprietary devices (Garmin).

## Why Apple Watch + Swift

- User already wears Apple Watch — data collection problem is solved
- HealthKit already has everything: HR, HRV, VO2 max, resting HR, all workout types
- Native Swift unlocks: HealthKit read/write, live Watch app, widgets, Live Activities
- RN HealthKit libraries incompatible with current stack — Swift is the only path

## HealthKit Integrations To Build

- **Write workouts** — saves to Health, shows in Activity rings and Fitness app
- **Real-time HR** — during workout, shown on screen and Watch face
- **HRV + resting HR trend** — pre-workout context panel
- **VO2 max** — Apple already calculates, just read and display it
- **Cross-workout history** — read all workout types to build personal baseline

## Differentiating Feature: Relative Effort

Show HR relative to *personal baseline* for that activity type and intensity — not generic zones. Example: "your HR hit 87% of max on a flat 9-min/mile — normally you do that at 82% — you were working harder than usual today."

Over time: daily readiness signal — go hard, go easy, or rest — based on HRV trend, resting HR, and recent training load across all activity types.

## Activity Types (broader than Ruck & Run)

- Run, Walk, Ruck (carry over from Ruck & Run)
- Lift / strength sessions
- Sport (soccer, etc.)
- Open / other

## Build Order

1. Learn SwiftUI — Hacking with Swift (Paul Hudson) is the go-to resource
2. **First real milestone:** open app → request HealthKit permissions → read last night's HRV and resting HR → display them. Teaches Swift + SwiftUI + HealthKit auth + async in one shot.
3. Add workout tracking (GPS + HR) — Ruck & Run feature set rebuilt in Swift
4. Add HealthKit write (save workouts to Health)
5. Add personal baseline model — needs a few weeks of data to get meaningful
6. Add Watch app — real-time stats on wrist during workout
7. Add daily readiness signal

## Product Potential

- Whoop is $30/mo and requires their hardware
- Garmin requires their devices
- Apple Fitness+ doesn't touch training intelligence
- Gap: Apple Watch native app that builds a personal model from HealthKit history and gives simple, actionable daily guidance — for people who train seriously across multiple modalities
