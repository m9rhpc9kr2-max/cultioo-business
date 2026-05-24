#!/bin/bash
set -e

cd "$(dirname "$0")/.."

ARCHIVE="build/ios/archive/Runner.xcarchive"
FRAMEWORK_DIR="$ARCHIVE/Products/Applications/Runner.app/Frameworks/objective_c.framework"
FRAMEWORK_BINARY="$FRAMEWORK_DIR/objective_c"
FRAMEWORK_PLIST="$FRAMEWORK_DIR/Info.plist"
EXPORT_OPTIONS="ios/ExportOptions.plist"
OUTPUT_DIR="build/ios/ipa_fixed"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cultioo Business - IPA Fix & Export"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Check archive exists
if [ ! -f "$FRAMEWORK_BINARY" ]; then
  echo "❌ Archive not found. Run 'flutter build ipa' first."
  exit 1
fi

# 2. Read MinimumOSVersion from Info.plist
MIN_OS=$(plutil -extract MinimumOSVersion raw "$FRAMEWORK_PLIST" 2>/dev/null || echo "13.0")
echo "📋 Framework MinimumOSVersion: $MIN_OS"
echo "📋 Current platform tag:"
vtool -show-build "$FRAMEWORK_BINARY" | grep -E "platform|minos|sdk" | xargs

# 3. Patch platform tag
echo "🔧 Patching objective_c.framework..."
vtool -set-build-version ios "$MIN_OS" 15.0 -replace \
  -output "${FRAMEWORK_BINARY}.fixed" "$FRAMEWORK_BINARY" 2>/dev/null
mv "${FRAMEWORK_BINARY}.fixed" "$FRAMEWORK_BINARY"

# 4. Re-sign
codesign --force --sign - "$FRAMEWORK_BINARY"
echo "✅ Patched & re-signed: platform=IOS minos=$MIN_OS"

# 5. Export IPA
rm -rf "$OUTPUT_DIR"
echo "📦 Exporting IPA..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$OUTPUT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  2>&1 | grep -E "error:|warning:|Export|✓|EXPORT|IPA|success" || true

if ls "$OUTPUT_DIR"/*.ipa 1>/dev/null 2>&1; then
  IPA_PATH=$(ls "$OUTPUT_DIR"/*.ipa | head -1)
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✅ IPA ready: $IPA_PATH"
  echo "   Drag & drop into Apple Transporter"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  open "$OUTPUT_DIR"
else
  echo "❌ Export failed. Check Xcode logs."
  exit 1
fi
