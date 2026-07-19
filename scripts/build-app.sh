#!/bin/bash
# Build the release binary and assemble a runnable DiskVis.app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/DiskVis.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DiskVis "$APP/Contents/MacOS/DiskVis"

if [ ! -f Resources/AppIcon.icns ]; then
  bash scripts/make-icon.sh
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>DiskVis</string>
	<key>CFBundleIdentifier</key>
	<string>com.local.diskvis</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>DiskVis</string>
	<key>CFBundleDisplayName</key>
	<string>DiskVis</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
