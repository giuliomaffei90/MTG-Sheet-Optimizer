#!/bin/bash
# Builds dist/MTG Sheet Optimizer.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="dist/MTG Sheet Optimizer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MTGSheetOptimizer "$APP/Contents/MacOS/"
cp Resources/* "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MTGSheetOptimizer</string>
    <key>CFBundleIdentifier</key><string>com.giuliomaffei.MTGSheetOptimizer</string>
    <key>CFBundleName</key><string>MTG Sheet Optimizer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
