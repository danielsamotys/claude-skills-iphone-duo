#!/usr/bin/env bash
# iPhone Duo readiness audit for a React Native / Expo app. Read-only.
#   bash audit.sh [app-dir] [extra-src-dir...]   # app-dir = the folder holding package.json (default: git root or cwd)
# Monorepo: pass the app package, plus shared UI packages the app renders, e.g. apps/mobile packages/ui/src.
set -u
EXTRA=(); for d in "${@:2}"; do EXTRA+=("$(cd "$d" && pwd)"); done
cd "${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 1
[ -f package.json ] || { echo "no package.json in $(pwd); pass the app folder" >&2; exit 1; }

DIRS=(); for d in src app components lib screens features modules hooks navigation; do [ -d "$d" ] && DIRS+=("$d"); done
[ ${#DIRS[@]} -eq 0 ] && DIRS=(.)
[ ${#EXTRA[@]} -gt 0 ] && DIRS+=("${EXTRA[@]}")
G=(--include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --exclude-dir=node_modules --exclude-dir=ios --exclude-dir=android
   --exclude-dir=dist --exclude-dir=build --exclude-dir=.expo --exclude-dir=__tests__ --exclude-dir=__mocks__)
g() { grep -rn "${G[@]}" "$@" "${DIRS[@]}" 2>/dev/null | grep -vE '\.(test|spec)\.[jt]sx?:'; }
nocomment() { grep -vE ':[0-9]+:[[:space:]]*(//|/?\*)'; }
count() { g "$@" | nocomment | wc -l | tr -d ' '; }
# installed version (works with hoisted monorepo deps), else the version declared in package.json, else "-"
ver() { node -p "require(require.resolve('$1/package.json',{paths:[process.cwd()]})).version" 2>/dev/null ||
  node -p "const p=require('./package.json');const v={...p.dependencies,...p.devDependencies}['$1'];v?v+' (declared)':'-'" 2>/dev/null || echo -; }
fc() { [ -f "$2" ] || { echo -; return; }; grep -c -- "$1" "$2"; }   # count matches in one file, "-" if the file is absent
APPDIR=$(dirname "$(ls ios/*/AppDelegate.* 2>/dev/null | head -1)" 2>/dev/null)
PLIST=${APPDIR:+$APPDIR/Info.plist}
EXPO=$(node -p "const p=require('./package.json');!!({...p.dependencies,...p.devDependencies}).expo" 2>/dev/null)

echo "app: $(pwd)   scanned: ${DIRS[*]}   expo: ${EXPO:-false}   native ios/: ${APPDIR:-none}"
if [ "$EXPO" = true ]; then
  echo "expo SDK: $(ver expo)   (SDK 58+ prebuild already adopts UIScene; older SDKs need it added)"
  git check-ignore -q ios 2>/dev/null && echo "ios/ is gitignored (Continuous Native Generation): every native fix must be app.json or a config plugin"
  [ -n "$APPDIR" ] && [ app.json -nt "$PLIST" ] && echo "WARNING: app.json is newer than $PLIST; ios/ may be stale, re-run prebuild before trusting sections 1 and 3"
fi

echo; echo "== 1. SDK / toolchain (blocker: built with an SDK < 27.1 = letterboxed on the inner display)"
echo "local Xcode:  $(xcodebuild -version 2>/dev/null | head -1)   iphoneos SDK: $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)"
echo "Duo sim type: $(xcrun simctl list devicetypes 2>/dev/null | grep -ci 'iPhone Duo') (device type known to CoreSimulator; 0 = no Xcode 27.1+ installed)"
for x in /Applications/Xcode*.app; do [ -d "$x" ] && echo "installed:    $x  Xcode $(defaults read "$x/Contents/Info" CFBundleShortVersionString 2>/dev/null)  iphoneos SDK $(DEVELOPER_DIR=$x/Contents/Developer xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)"; done
R=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CI=$(grep -rhoE "xcode-version:.*|runs-on:.*macos[^ ]*|xcode: *\"?[0-9.]+" "$R"/.github/workflows "$R"/.circleci "$R"/bitrise.yml "$R"/codemagic.yaml 2>/dev/null | sort -u)
echo "${CI:-no macOS CI job found (iOS builds happen locally or on EAS)}" | sed 's/^/CI:           /'
[ -f eas.json ] && { E=$(grep -oE '"image": *"[^"]+"' eas.json | sort -u); echo "${E:-no image pinned = EAS default image; check which Xcode it ships}" | sed 's/^/EAS:          /'; }
echo "UIScene lifecycle (iOS 27 SDK builds trap at launch without it): manifest=$(fc UIApplicationSceneManifest "$PLIST") scene-delegate=$(ls "$APPDIR"/*SceneDelegate* 2>/dev/null | wc -l | tr -d ' ')"
echo "pod targets with deployment target < 15 (Xcode 27 build error; a finding only if > 0): $(fc 'IPHONEOS_DEPLOYMENT_TARGET = \(9\|1[0-4]\)\.' ios/Pods/Pods.xcodeproj/project.pbxproj)   Podfile clamp: $(fc "IPHONEOS_DEPLOYMENT_TARGET'\] *=" ios/Podfile)"

echo; echo "== 2. Dependencies"
for p in react-native expo react-native-screens react-native-safe-area-context @react-navigation/native-stack @react-navigation/stack @react-navigation/drawer expo-router react-native-modal @gorhom/bottom-sheet; do
  v=$(ver "$p"); [ "$v" != - ] && printf "%-34s %s\n" "$p" "$v"
done
echo "native stacks: createNativeStackNavigator $(count createNativeStackNavigator), expo-router <Stack> layouts $(g -l "<Stack" | grep -c "_layout\.")   headerShown: false: $(count -E "headerShown: *false")   (react-native-screens >= 4.30.0 fixes Duo native-stack HEADERS; moot when 0 or every header is hidden)"
echo "react-native-modal with avoidKeyboard: $(count -E "avoidKeyboard")   (padding passed in its style is applied twice; see adaptive-layout)"

echo; echo "== 3. Native config"
if [ "$EXPO" = true ]; then
  if [ -f app.json ] && node -e "process.exit(require('./app.json').expo?0:1)" 2>/dev/null; then
    node -e "const e=require('./app.json').expo;console.log('app.json orientation:',e.orientation??'(unset = default)','| ios.requireFullScreen:',e.ios?.requireFullScreen??'(unset)','| ios.supportsTablet:',e.ios?.supportsTablet??'(unset)')"
  fi
  for f in app.config.js app.config.ts; do [ -f "$f" ] && grep -nE "orientation|requireFullScreen|supportsTablet" "$f" | sed "s|^|$f:|" | head -5; done   # read, never executed
fi
if [ -n "$PLIST" ]; then
  for k in UISupportedInterfaceOrientations 'UISupportedInterfaceOrientations~ipad' UIRequiresFullScreen; do
    v=$(plutil -extract "$k" json -o - "$PLIST" 2>/dev/null | sed 's/UIInterfaceOrientation//g'); [ -n "$v" ] && echo "Info.plist $k: $v"
  done
fi
echo "(UIRequiresFullScreen true = letterboxed when open; a portrait-only list alone is fine on the inner display)"
echo "AppDelegate orientation gate: $(fc supportedInterfaceOrientationsFor "$(ls "$APPDIR"/AppDelegate.* 2>/dev/null | head -1)")"
grep -rn "UIScreen.main" ios --include='*.swift' --include='*.m' --include='*.mm' 2>/dev/null | grep -vE 'ios/(Pods|build)/' | head -5

echo; echo "== 4. Stale size reads (captured once; wrong after the first fold / unfold / Split View resize)"
echo "module-scope Dimensions.get:       $(g -E "^(const|let|var|export const) .*Dimensions\.get\(" | wc -l | tr -d ' ')"
echo "any Dimensions.get:                $(count "Dimensions.get")   (useWindowDimensions: $(count useWindowDimensions))"
echo "Dimensions.get('screen'):          $(count "Dimensions.get('screen')")   (the display, not your window)"
echo "Dimensions.addEventListener:       $(count "Dimensions.addEventListener")"
echo "--- first module-scope read per file (height*x = sheet/modal, width = paging/grid, both = full-screen media):"
g -E "^(const|let|var|export const) .*Dimensions\.get\(" | nocomment | sort | awk -F: '!seen[$1]++ {sub(/^[ \t]+/,"",$3); printf "%s:%s  %s\n",$1,$2,substr($0,index($0,$3))}' | cut -c1-160 | head -40

echo; echo "== 5. Device heuristics instead of size / insets"
g -E "isIphoneX|hasNotch|hasDynamicIsland|getStatusBarHeight|iphone-x-helper|Platform\.isPad|isTablet|getDeviceType|(height|width) *>= *(812|844|852|896|926|932)" | nocomment | head -25

echo; echo "== 6. Orientation checks in JS (branch on width instead)"
g -iE "lockToPortrait|lockAsync|isLandscape|isPortrait|getOrientationAsync|useDeviceOrientation" | nocomment | head -10

echo; echo "== 7. Insets: symmetric math, top-only padding (closed Duo = right: 84)"
g -E "Math\.max\(insets|insets\.(left|right) \* 2|insets\.left \|\| insets\.right" | head -5
echo "core SafeAreaView from 'react-native': $(g "SafeAreaView" | grep -c "from 'react-native'")"
echo "top inset without a right inset (check each for right-hand controls; shared screen wrappers first):"
for f in $(g -lE "insets\.top|edges *=" | cut -d: -f1 | sort -u); do
  grep -qE "insets\.top|edges *= *\{?\[[^]]*['\"]top['\"]" "$f" || continue
  grep -qE "insets\.(left|right)|['\"]right['\"]" "$f" || echo "  $f$(grep -oE "edges *= *\{?\[[^]]*\]" "$f" | head -1 | sed 's/^/   /')"
done

echo; echo "== 8. AppState (Split View leaves a VISIBLE app 'inactive'; pause on 'background' only)"
g -E "=== *'active'|!== *'active'|match\(/inactive\|background/\)|focusManager\.setFocused" | grep -iE "appState|nextState|status|state|focusManager" | nocomment | head -15
echo "(React Query: focusManager.setFocused(state === 'active') pauses refetchInterval polling in a visible Split View app)"

echo; echo "== 9. Hardcoded keyboard / header offsets"
g -E "keyboardVerticalOffset=\{-?[0-9]+\}" | head -10
