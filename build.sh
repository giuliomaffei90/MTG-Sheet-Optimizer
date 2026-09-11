#!/bin/bash
# Builds dist/MTG Sheet Optimizer.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="dist/MTG Sheet Optimizer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MTGSheetOptimizer "$APP/Contents/MacOS/"
cp spec/Resources/* "$APP/Contents/Resources/"
# AppIcon.icon is an Icon Composer document: actool compiles it into Assets.car (Liquid Glass on
# macOS 26) plus AppIcon.icns for older macOS.
xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --app-icon AppIcon \
  --include-all-app-icons --platform macosx --target-device mac --minimum-deployment-target 14.0 \
  --output-partial-info-plist "$(mktemp)" >/dev/null

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MTGSheetOptimizer</string>
    <key>CFBundleIdentifier</key><string>com.giuliomaffei.MTGSheetOptimizer</string>
    <key>CFBundleName</key><string>MTG Sheet Optimizer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
# Make Finder and the Dock pick up the new icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $APP"
