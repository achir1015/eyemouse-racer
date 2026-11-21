#!/bin/bash
# 在 Mac 上：Godot 匯出 Xcode 專案 → xcodebuild 封存 → 匯出 Ad Hoc .ipa（iPhone／iPad 都能裝，限已登記的裝置）。
# 要在 Mac 的「終端機」App 裡執行（SSH 進來時鑰匙圈是鎖的，簽章會失敗）：
#   osascript ~/Developer/eyemouse-racer/platform/ios/run-in-terminal.applescript "bash ~/Developer/eyemouse-racer/platform/ios/build-ipa.sh"
# 產出：~/Developer/eyemouse-racer-build/EyeMouseRacer-ios.ipa；log 在 ipa.log，完成留下 ipa.done（ok／fail）
PROJ=~/Developer/eyemouse-racer
OUT=~/Developer/eyemouse-racer-build/ios
GODOT=~/Developer/godot/Godot.app/Contents/MacOS/Godot
VERSION=$(grep -E '^config/version=' "$PROJ/project.godot" | cut -d'"' -f2)
BUILD=$(awk '/name="iOS"/{f=1} f && /^application\/version=/{print; exit}' "$PROJ/export_presets.cfg" | cut -d'"' -f2)

rm -rf "$OUT"
mkdir -p "$OUT"
exec > >(tee "$OUT/../ipa.log") 2>&1
set -o pipefail
fail() { echo "fail" > "$OUT/../ipa.done"; exit 1; }
rm -f "$OUT/../ipa.done"

echo "== 匯出 Xcode 專案 v$VERSION ($BUILD)"
"$GODOT" --headless --path "$PROJ" --import >/dev/null 2>&1
"$GODOT" --headless --path "$PROJ" --export-release "iOS" "$OUT/EyeMouseRacer.ipa" 2>&1 | grep -E "ERROR|DONE" || true
[ -d "$OUT/EyeMouseRacer.xcodeproj" ] || fail

cd "$OUT"
SETTINGS=(CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=7BN6XJ59KP
	INFOPLIST_KEY_CFBundleDisplayName="眼動賽車" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD")
echo "== 封存"
xcodebuild -project EyeMouseRacer.xcodeproj -scheme EyeMouseRacer -configuration Release \
	-destination 'generic/platform=iOS' -archivePath build/EyeMouseRacer.xcarchive \
	-allowProvisioningUpdates "${SETTINGS[@]}" archive | grep -E 'error|warning: .*sign|ARCHIVE' || fail
echo "== 匯出 .ipa"
xcodebuild -exportArchive -archivePath build/EyeMouseRacer.xcarchive -exportPath build/export \
	-exportOptionsPlist "$PROJ/platform/ios/ExportOptions.plist" -allowProvisioningUpdates || fail
IPA=$(ls build/export/*.ipa | head -1)
[ -f "$IPA" ] || fail
cp "$IPA" "$OUT/../EyeMouseRacer-ios.ipa"
unzip -p "$OUT/../EyeMouseRacer-ios.ipa" 'Payload/*.app/embedded.mobileprovision' | security cms -D | plutil -extract ProvisionedDevices json -o - - || true
ls -l "$OUT/../EyeMouseRacer-ios.ipa"
echo "ok" > "$OUT/../ipa.done"
