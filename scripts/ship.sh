#!/bin/bash
# Archive and upload a build to App Store Connect / TestFlight.
# Usage: ./scripts/ship.sh <build_number>
set -euo pipefail

BUILD_NUMBER=${1:?Usage: ./scripts/ship.sh <build_number>}
cd "$(dirname "$0")/.."
ARCHIVE_PATH="build/RuckRun.xcarchive"

echo "==> Ruck & Run build $BUILD_NUMBER"
rm -rf build
xcodegen generate --quiet

echo "==> Archiving..."
xcodebuild \
  -project HybridAthlete.xcodeproj \
  -scheme HybridAthlete \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

echo "==> Uploading to App Store Connect..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist exportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates

echo "==> Uploaded build $BUILD_NUMBER. It shows up in TestFlight after Apple finishes processing (~10-30 min)."
