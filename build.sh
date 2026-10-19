#!/bin/bash
# Applix — Full build script
# Builds both shell APK templates + container app, copies final APK to bin/
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
SHELL_DIR="$SCRIPT_DIR/src/shell_apk"
SHELL_WEB_DIR="$SCRIPT_DIR/src/shell_apk_web"
CONTAINER_DIR="$SCRIPT_DIR/src/container_app"

echo "================================"
echo "  Applix Build"
echo "================================"
echo ""

# Step 1: Build full shell APK template
echo "> Building full shell APK..."
cd "$SHELL_DIR"
./gradlew assembleRelease -q
cp app/build/outputs/apk/release/app-release.apk "$CONTAINER_DIR/assets/shell_template.apk"
echo "OK: full shell built and copied"
echo ""

# Step 2: Build web-only shell APK template
echo "> Building web shell APK..."
cd "$SHELL_WEB_DIR"
./gradlew assembleRelease -q
cp app/build/outputs/apk/release/app-release.apk "$CONTAINER_DIR/assets/shell_template_web.apk"
echo "OK: web shell built and copied"
echo ""

# Step 3: Build container app
echo "> Building container app..."
cd "$CONTAINER_DIR"
flutter build apk --release
echo ""

# Step 4: Copy to bin/
mkdir -p "$BIN_DIR"
cp build/app/outputs/flutter-apk/app-release.apk "$BIN_DIR/Applix.apk"
echo "OK: build complete: bin/Applix.apk"
echo ""

# Step 5: Install if device connected
if adb devices 2>/dev/null | grep -q "device$"; then
    echo "> Installing on device..."
    adb install -r "$BIN_DIR/Applix.apk"
    echo "OK: installed"
else
    echo "No device connected. APK ready at bin/Applix.apk"
fi
