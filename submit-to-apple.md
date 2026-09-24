# Submit Ruck & Run to the App Store

---

## Step 1 — Screenshots

**Chrome DevTools won't work** — this is a native iOS app, not a web page. You need the Xcode Simulator.

### Required sizes
App Store Connect requires at least one screenshot for each size you provide. Only the 6.9" is required; 6.5" is strongly recommended since many users have older iPhones.

| Size | Device it represents | Required? |
|------|----------------------|-----------|
| 6.9" (1320 × 2868 px) | iPhone 16 Pro Max | Yes |
| 6.5" (1242 × 2688 px) | iPhone 11 Pro Max / XS Max | Recommended |

Do **not** bother with iPad unless you explicitly support it.

### How to take screenshots in the Simulator

1. Open Xcode → open `ios/RuckRun.xcworkspace`
2. Select a simulator target — use **iPhone 16 Pro Max** for 6.9", **iPhone 11 Pro Max** for 6.5"
3. Hit **Run** (▶) — the simulator boots and launches the app
4. Navigate to the screen you want to capture
5. Press **Cmd + S** — screenshot saves to your Desktop automatically
6. Repeat for each screen you want

### What screens to capture (suggested)
- [ ] Main screen — activity picker (Run / Walk / Ruck)
- [ ] Active tracking screen — map with route drawing, stats visible
- [ ] Finished run detail — map + elevation/pace charts
- [ ] History list — showing a few past activities
- [ ] Share card — the dark card with stats (optional but looks great)

### Tips
- Add some fake run data before screenshotting so the history and charts don't look empty
- The simulator won't have real GPS — for the active tracking screen, fake it by going to **Features → Location → City Bicycle Ride** in the Simulator menu bar while the app is tracking
- Screenshots must be exact pixel dimensions — Simulator captures at the right size automatically, don't resize them

---

## Step 2 — App Store Connect Metadata

Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Your Apps → Ruck & Run → press **+** next to iOS App → enter version 1.0.0.

### App Information (one-time, not per version)
- [ ] **App name:** Ruck & Run
- [ ] **Subtitle** (30 chars max): `Track runs, walks & rucks`
- [ ] **Category:** Health & Fitness (primary), Sports (secondary)
- [ ] **Privacy Policy URL:** https://jwatsondev.github.io/simple-run/privacy

### Version Metadata (fill in for 1.0.0)
- [ ] **Description** — first paragraph must be upfront about no Apple Health. Example:

  > Ruck & Run does not integrate with Apple Health or HealthKit. All data is stored on your device only. If Apple Health sync is a must-have for you, this app isn't for you.
  >
  > Simple GPS tracking for runs, walks, and rucks. No subscription. No account. No bloat. Start an activity, watch your route draw on the map, and review your history when you're done.
  >
  > Features:
  > • Run, Walk, or Ruck tracking
  > • Background GPS — keeps tracking when your screen locks
  > • Live pace, distance, and time
  > • Route map with full polyline
  > • Elevation and pace charts
  > • Share card — dark card with your stats and route
  > • Full activity history

- [ ] **Keywords** (100 chars max): `run tracker,ruck,walk,GPS,no subscription,simple,outdoor,fitness,pace,distance`
- [ ] **Support URL:** https://jwatsondev.github.io/simple-run
- [ ] **What's New:** leave blank for a 1.0 release (or write: "First release.")
- [ ] **Screenshots:** upload what you captured in Step 1

---

## Step 3 — Build & Age Rating

- [ ] **Build:** select Build 12 from the dropdown (it's already on TestFlight — it will appear here)
- [ ] **Age rating:** click "Edit" next to Age Rating and complete the questionnaire. Answer No to everything — should land at **4+**

---

## Step 4 — Review Notes & Legal

### Notes for Apple Reviewer
In the "Notes" field under App Review Information, paste this:

> This app uses background location to continue GPS tracking when the user's screen locks during an active run, walk, or ruck. No sign-in is required. To test: tap Start Run on the main screen, lock the device, wait a few seconds, unlock — the distance and route should continue updating.

- [ ] Sign-in required? **No** — leave demo account fields blank

### Export Compliance
- [ ] Click through the encryption questionnaire
- Answer **Yes** to "does your app use encryption" (standard HTTPS counts)
- Answer **No** to exemption — select **"Complies with US encryption regulations"**
- This is standard for almost every app, don't overthink it

### Privacy Nutrition Labels
- [ ] Under "App Privacy" → "Data Types": this app collects nothing and sends nothing off-device
- Select **"Data Not Collected"** for all categories
- The only data used is Location — and it stays on device — so no disclosure is required

---

## Step 5 — Final Checks Before Submitting

- [ ] App icon looks correct in the App Store Connect preview (not blurry, not clipped)
- [ ] All screenshot sizes uploaded and look good in preview
- [ ] Support and Privacy URLs both load correctly in a browser
- [ ] Description first paragraph calls out no Apple Health
- [ ] Build 12 is selected
- [ ] No automated issues flagged by App Store Connect (red warnings at top of page)

Hit **Submit for Review**.

---

## After Submission

- First-time submissions typically take **24–48 hours** for review
- Watch your email — App Store Connect will notify you of approval or rejection
- If rejected: read the rejection reason fully before doing anything. Do not resubmit without directly addressing the stated reason.
- Common first-submission rejections: missing privacy policy, insufficient background location justification, screenshots don't match the app
