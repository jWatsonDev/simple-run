#!/bin/bash
set -e

BUILD_NUMBER=${1:?Usage: ./scripts/build.sh <build_number>}
MARKETING_VERSION="1.0.0"
WORKSPACE="ios/RuckRun.xcworkspace"
SCHEME="RuckRun"
ARCHIVE_PATH="build/RuckRun.xcarchive"
EXPORT_PATH="build/export"
IPA_PATH="$EXPORT_PATH/RuckRun.ipa"

echo "==> Building Ruck & Run v$MARKETING_VERSION ($BUILD_NUMBER)"

# Clean previous build artifacts
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

# Archive
echo "==> Archiving..."
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

# Export IPA
echo "==> Exporting IPA..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist exportOptions.plist \
  -exportPath "$EXPORT_PATH"

echo "==> IPA ready: $IPA_PATH"

# Submit to TestFlight
echo "==> Submitting to TestFlight..."
eas submit --platform ios --path "$IPA_PATH" --non-interactive

echo "==> Done! Build $BUILD_NUMBER submitted to TestFlight."
