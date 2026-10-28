#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iOS requires macOS and Xcode; this script cannot build on Linux/Windows.' >&2
  exit 2
fi
command -v flutter >/dev/null
xcodebuild -version
xcrun simctl list devices available --json > /tmp/durak-ios-devices.json
DURAK_SIM_ID="${DURAK_SIM_ID:-$(python3 -c 'import json; d=json.load(open("/tmp/durak-ios-devices.json")); print(next(x["udid"] for group in d["devices"].values() for x in group if x["name"].startswith("iPhone")))')}"
mkdir -p docs/qa/ios
flutter pub get
flutter analyze
flutter test --reporter expanded
xcrun simctl boot "$DURAK_SIM_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DURAK_SIM_ID" -b
flutter build ios --simulator --debug
xcrun simctl install "$DURAK_SIM_ID" build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$DURAK_SIM_ID" dev.duraknearby.durakBt
xcrun simctl terminate "$DURAK_SIM_ID" dev.duraknearby.durakBt
if [[ "$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')" == 3.35.7 ]]; then
  python3 tool/patch_flutter_ios_test.py "$(python3 -c 'import pathlib,shutil; print(pathlib.Path(shutil.which("flutter")).resolve().parent.parent)')"
fi
flutter test integration_test/app_test.dart -d "$DURAK_SIM_ID" --dart-define=TEST_MODE=true --reporter expanded
xcrun simctl launch "$DURAK_SIM_ID" dev.duraknearby.durakBt
sleep 3
xcrun simctl io "$DURAK_SIM_ID" screenshot docs/qa/ios/simulator.png
mkdir -p dist
(cd build/ios/iphonesimulator && ditto -c -k --sequesterRsrc --keepParent Runner.app ../../../dist/DurakNearby-ios-simulator.zip)
# This validates arm64 device compilation, but the resulting bundle is unsigned.
flutter build ios --release --no-codesign
(cd build/ios/iphoneos && ditto -c -k --sequesterRsrc --keepParent Runner.app ../../../dist/DurakNearby-ios-unsigned.zip)
DURAK_PROJECT_DIR="$PWD"
DURAK_IPA_STAGE="$(mktemp -d -t durak-ipa)"
mkdir -p "$DURAK_IPA_STAGE/Payload"
ditto build/ios/iphoneos/Runner.app "$DURAK_IPA_STAGE/Payload/Runner.app"
(cd "$DURAK_IPA_STAGE" && ditto -c -k --sequesterRsrc --keepParent Payload "$DURAK_PROJECT_DIR/dist/DurakNearby-ios-unsigned.ipa")
python3 tool/verify_ipa.py dist/DurakNearby-ios-unsigned.ipa dist/ios-build-info.json
echo 'Unsigned device IPA created. Install using local signing (AltStore/AltServer) or sign in Xcode.' 
