---
description: Build, export, and submit Ruck & Run to TestFlight
argument-hint: <build_number>
allowed-tools: [Read, Edit, Bash, Write]
---

# /ship — Ruck & Run Build & Submit

Ship a new build to TestFlight.

## Arguments

Build number provided: $ARGUMENTS

## Instructions

1. **Validate argument** — if no build number was provided, ask the user for one before proceeding.

2. **Run the build script:**
   ```bash
   ./scripts/build.sh <build_number>
   ```
   This will archive, export the IPA, and submit to TestFlight via `eas submit`. It takes ~5-10 minutes. Run it and wait for completion.

3. **On success — update RELEASES.md:**
   - Read the current RELEASES.md
   - Add a new entry at the top (below the `# Ruck & Run — Release History` heading) for this build number
   - Copy the feature list from the previous build entry since features are the same unless the user specified changes
   - Mark status as "Submitted to TestFlight"
   - Include today's date

4. **Commit everything:**
   - Stage: `RELEASES.md`, `ios/RuckRun.xcodeproj/project.pbxproj`, and any other modified tracked files (but NOT the `build/` directory)
   - Commit with message: `Ship build <number> to TestFlight`

5. **Update openbrain memory** — call `remember` on project "dadhabit" with the new build number and submission status.

6. **Report to user** — confirm build number, that it's in TestFlight, and remind them it usually takes a few minutes to process before appearing in the TestFlight app.
