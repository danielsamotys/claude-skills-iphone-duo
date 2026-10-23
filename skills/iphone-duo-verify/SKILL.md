---
name: iphone-duo-verify
description: Use when asked to test, verify, screenshot or QA a React Native app on iPhone Duo (Apple's foldable) in the iOS simulator. That covers the closed/outer display, the open/inner display, fold/unfold, rotation and Split View, including when the Duo simulator (Xcode 27.1+) is not installed, and when iphone-duo-adaptive-layout work needs a simulator pass before a PR.
---

# Verify on iPhone Duo

**Evidence rule: a screenshot counts only if its logical size (pixels ÷ 3, printed by `duo-pose.sh shot`) matches the pose you claim.** A phone or iPad screenshot is never Duo evidence; it is a *proxy* and is labeled as one. Facts and point sizes: `../iphone-duo-adaptive-layout/references/iphone-duo-facts.md`. Scripts below live in this skill's `scripts/` folder; `$S` is that folder.

## Gate: run first, report the result verbatim

```bash
for x in /Applications/Xcode*.app; do echo "$x $(defaults read "$x/Contents/Info" CFBundleShortVersionString)"; done   # 27.1+ may sit next to the default
xcrun simctl list runtimes | grep "iOS 27.1"          # the Duo runtime (device types are shared, so they prove nothing)
xcrun simctl list devices | grep "iPhone Duo"         # an existing Duo sim to reuse
```

| Result | Path |
|---|---|
| An Xcode 27.1+ is installed **and** the iOS 27.1 runtime is present | **Real pass** below |
| Either is missing | **Proxy pass** below. The report's first line says Duo verification is blocked by the toolchain and names what is installed |

Never install Xcode or runtimes to unblock yourself. Say what's needed and stop at the proxy.

## Pre-flight: before the first build

Run every command with `export DEVELOPER_DIR=<Xcode 27.1>.app/Contents/Developer`, and leave the default Xcode alone. The order is: create and boot the sim (Real pass step 1), grant permissions, then build and launch. If the app is already installed and permissions are granted, skip to the Metro check.

- **iOS 27 SDK prerequisites:** UIScene adoption and the pod deployment-target clamp (`../iphone-duo-adaptive-layout/references/native-ios.md`, steps 1–2). Without them the build fails or the app traps at launch. That is a finding: report it and hand it to `iphone-duo-adaptive-layout`, which owns the fix. **Expo:** the fix must live in a config plugin before `npx expo run:ios`, because that command re-runs prebuild and regenerates `ios/`.
- **Permissions:** `xcrun simctl privacy <UDID> grant all <bundleId>`, then `shutdown` and `boot`. tccd caches, so grant before the first launch or reboot afterwards. That beats tapping alerts.
- **Metro:** a debug build loads JS from Metro. Check that `curl -s localhost:<port>/status` prints `packager-status:running` before any flow. If 8081 belongs to another project, start Metro on another port and point the app at it: `xcrun simctl spawn <UDID> defaults write <bundleId> RCT_jsLocation localhost:<port>`.
- **xcodebuild exit 65 behind the RN CLI:** rerun `xcodebuild -workspace ios/<App>.xcworkspace -scheme <App> -destination id=<UDID> -derivedDataPath ios/build build` and grep `error:`. If `simctl install` then fails with "Invalid placeholder attributes", an app extension lacks `CFBundleVersion`: add `CURRENT_PROJECT_VERSION=<CFBundleVersion>` to the command.
- **Post-login screens:** if the repo already has Maestro or E2E flows that sign in or register a throwaway account against a test backend, reuse them. Otherwise the user signs in a test account by hand. Never use real customer data, and never type real credentials.

## Real pass (Xcode 27.1+)

### 1. Simulator

Reuse a Duo sim from the gate's device list (boot it if it is shut down). Create one only if none exists:

```bash
xcrun simctl create "Duo-QA" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo com.apple.CoreSimulator.SimRuntime.iOS-27-1
xcrun simctl boot <UDID>
```

If the runtime is missing, `xcodebuild -downloadPlatform iOS` fetches it (≈8 GB); that is the user's call. Build with `npx react-native run-ios --udid <UDID>` / `npx expo run:ios --device <UDID>`, or `simctl install` a built `.app`.

### 2. Poses and screenshots

The poses are Device Hub buttons; `simctl` has none. `duo-pose.sh` opens Device Hub, clicks the poses (the terminal needs Accessibility access), and screenshots one display:

```bash
bash $S/duo-pose.sh <UDID> hub
bash $S/duo-pose.sh <UDID> pose Closed;          bash $S/duo-pose.sh <UDID> shot home-closed.png outer        # 466×678
bash $S/duo-pose.sh <UDID> pose "Rotate Right";  bash $S/duo-pose.sh <UDID> shot home-closed-landscape.png outer   # stays 466×678
for i in 1 2 3; do bash $S/duo-pose.sh <UDID> pose "Rotate Right"; done                                       # back upright before unfolding
bash $S/duo-pose.sh <UDID> pose Open;            bash $S/duo-pose.sh <UDID> shot home-open.png inner          # 951×669, native landscape
bash $S/duo-pose.sh <UDID> pose "Rotate Right";  bash $S/duo-pose.sh <UDID> shot home-open-rotated.png inner  # 669×951
bash $S/duo-pose.sh <UDID> pose "Partially Open"                                                            # tent; renders like Open
```

- `pose` waits 4 s. Add nothing unless the shot comes back black. Clicking the current pose is harmless.
- Rotation is cumulative: count your Rotate Rights (4 = upright). There is no Rotate Left.
- Closed poses render on the **outer** display, so always pass `outer` or `inner`. After a boot, don't assume which display is live; shoot both and keep the one with content.
- Run poses on an idle machine. Under load (jest, a build) the AppleEvent times out (`-1712`), the pose never applies and the shot is black. Check every shot's size and content.
- Both displays black after a shutdown/boot means the sim is wedged. Shutdown and boot once more, then relaunch the app. Still black → "Not verified", with that reason.

### 3. Driving the app (Maestro)

Maestro needs Java 17+ (`JAVA_HOME`). Open Device Hub (`duo-pose.sh hub`) and set `pose Closed` before every flow. A flow only *navigates*: it launches the app, dismisses launch dialogs and reaches the screen, then ends with the app on that screen, and you run the poses from the shell. Reach screens the cheapest way your app allows:

- **Deep link:** `- openLink: myapp://item/42`. This is the most robust way to reach detail screens.
- **Tabs** (React Navigation, expo-router): `tapOn: { id: "<tabBarButtonTestID>" }`, or the tab's label. Icon-only tabs have no text: use a testID, or a point from the hierarchy.
- **React Navigation drawer:** the bundled `scripts/open-drawer-item.yaml` (tested on the Duo sim):

```yaml
appId: com.example.app
---
- launchApp
- extendedWaitUntil: { visible: "<text on your first screen>", timeout: 90000 }   # a dev cold launch via Metro took ~40 s
- runFlow: { file: /abs/path/to/iphone-duo-verify/scripts/open-drawer-item.yaml, env: { APP_ID: com.example.app, MENU: "7%,6%", ITEM: "Settings" } }
```

Wrap every navigation tap in `repeat: { times: 3, while: …, commands: [ tapOn …, waitForAnimationToEnd ] }`. The drawer step shows the pattern.

What Maestro can and can't do on the Duo sim:

- **Drive flows on the closed display.** Text taps work there. On the inner display hierarchy bounds come back skewed (a dialog at x = −169), so change poses only between shots.
- **Untexted controls** (hamburger, close icons): find their bounds with `maestro --device <UDID> hierarchy` and tap them as a point. Screenshot pixels are ÷ 3; never estimate points from a picture.
- **Screenshots:** `takeScreenshot` is black on the Duo sim. Use `duo-pose.sh shot`.
- **Dialogs that are one accessibility element** have no separate "Close" node. `tapOn: "Close"` with `optional: true` silently does nothing, and your next tap lands on the dialog. Tap by point and assert the dialog is gone.
- **Synthesized taps are sometimes dropped**, most often the first tap inside a drawer after launch. Manual clicks work, and an iOS 27.0 iPhone receives the same taps, so it is not an app bug. Wrap navigation taps in `repeat … while`. Don't add "warm-up" taps: when one isn't dropped, it acts.
- **System UI is unreachable** (Control Center, the multitasking control), so Split View can't be entered on the sim.
- **Dev menu:** if it opens, Maestro taps its items. Relaunch the app.
- **macOS has no `timeout`:** `timeout 90 maestro …` fails silently and never runs. Use your tool's timeout.
- A flow that still fails: rerun it once, then read `maestro hierarchy` to see where it stopped.

### 4. Matrix

For each cell, record the logical W×H printed by `duo-pose.sh shot` and save the shot as `<qa-dir>/<screen>-<pose>.png`, where `<qa-dir>` is the repo's QA or docs folder (e.g. `qa/duo-<date>/`). `<screen>` is kebab-case. The pose is one of `closed`, `closed-landscape`, `open`, `open-rotated`, `partial`, plus `refold` for the outer shot after fold → unfold → fold. If an earlier QA report exists, read it first: a screen already triaged needs a re-shot, not a re-investigation.

| Pose | Shoot | Expect W×H (≈) | Check |
|---|---|---|---|
| Closed, portrait | outer | 466×678 | Nothing regressed versus a normal iPhone. **No button, text or input in the right 84 pt**: the closed Duo reports insets `{top: 0, right: 84, bottom: 34}`. Backgrounds, header bars and images may run edge to edge |
| Closed, landscape | outer | 466×678 | Stays portrait; nothing lost |
| Open, upright (native landscape) | inner | 951×669 | Letterboxed into a centered ~466-wide window = portrait lock or old SDK, a **failure**. If the audit already found the lock, record the failure, finish the other rows, and hand the lock to `iphone-duo-adaptive-layout` (native-ios.md step 3). Otherwise: wide layout, and sheets and modals are not sized off a stale height |
| Open, rotated | inner | 669×951 | Wide layout on; drawer permanent (if adopted); reading content capped and centered; no stretched thumbnails |
| Partially Open | inner | 951×669 | Same verdict as Open upright |
| **Fold → unfold → fold on the same screen** | outer (`closed`) → inner, Open upright (`open`) → outer (`refold`) | changes live | Layout follows **without** navigating away; this is the test a module-scope `Dimensions.get` fails. Also unfold while a screen is pushing or loading |
| Split View, left then right (skip if `UIRequiresFullScreen`) | inner | ~300–650 wide | Hardware only on the 27.1 sim → "Not verified (hardware only)". On a device: side insets differ, and the camera and timers keep running while `inactive` |

### 5. Screens, in order

Pick from what the app has: login or onboarding (carousels snap to the new width), home (header, tabs or drawer), one list or grid, one detail screen (images and long text), one bottom sheet or modal, one screen with the keyboard up (chat, form), one camera screen. Reach each with a Maestro flow.

## When a result looks wrong: measure before blaming layout

| Symptom | Measure | What it turned out to be (in one production app) |
|---|---|---|
| A screen keeps its old width after a fold | Temporary 500 ms JS heartbeat: `setInterval(() => fetch('http://localhost:<port>/hb'), 500)` plus a tiny local HTTP listener | A 35–44 s JS freeze from 360 rows in a ScrollView. The resize was queued, not missed |
| Layout narrower than the screen on the closed display | Log `useSafeAreaInsets()` / `initialWindowMetrics` | `right: 84` is reserved. Ending at 382 pt is correct; reaching 466 pt is the suspect |
| "Drawer stuck open" | Navigator state (`history` contains `{type: 'drawer', status: 'open'}`) plus an `onPressIn` probe on the item | The press never arrived (the dropped-tap quirk above) |
| Duo-only or iOS 27? | The 27.1 runtime has only the Duo. Create an iPhone on the **27.0** runtime, install the same build, and repeat the flow | — |

Remove every probe before committing.

## Proxy pass (no Duo simulator)

The closed Duo is a compact-width iPhone, so ordinary iPhone QA already covers it. **Don't run an iPhone proxy.** Proxy only the open display's regular width:

| Proxy for | Simulator | Shows | Cannot show |
|---|---|---|---|
| Inner display (open) | **iPad mini** (744×1133; needs iPad support — `TARGETED_DEVICE_FAMILY` with 2, or Expo `ios.supportsTablet: true` — otherwise it runs as a scaled iPhone and proves nothing) | wide branch, permanent drawer, reading-column caps, tile grids | fold resize, Duo insets, the exact 669 pt width |
| Resize at runtime | **iPad on iOS 26+** in a resizable window (drag its edge) | layout following a live width change | Duo insets, poses |

Caption every screenshot "proxy (iPad mini)". Split View can't be proxied → "Not verified". One build at most; it's a smoke check.

## Report shape

1. Gate result: versions, and whether the device type is present.
2. Matrix: pose → logical size measured → pass/fail → screenshot path. Proxy rows say "proxy".
3. Failures as `file:line` + pose, handed back to `iphone-duo-adaptive-layout`.
4. "Not verified": every cell you could not run, and why. Never leave a cell blank.

## Common mistakes

| Mistake | Fix |
|---|---|
| Calling an iPad or iPhone screenshot "Duo" | Label it proxy |
| Verifying each pose on a fresh launch only | Fold/unfold **on the same screen** is the real test |
| Calling the letterboxed Open-upright pose "lock honored" | Half the inner display is black; it's a failure |
| Estimating tap points from a screenshot | Pixels ÷ 3. Tap by text, or by point from hierarchy bounds |
| Testing Split View with `UIRequiresFullScreen = true` | The app opted out; the row is N/A, and say so |
| Fixing what a measurement hasn't confirmed | Use the table above first. Two "Duo bugs" in the reference app were a JS freeze and a test-tool quirk |
| Installing Xcode 27.1 to unblock | Toolchain changes are the user's call; report and stop |
