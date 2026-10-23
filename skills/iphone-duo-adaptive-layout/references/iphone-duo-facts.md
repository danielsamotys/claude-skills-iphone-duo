# iPhone Duo: facts that matter to a React Native app

Everything marked **measured** was measured on the Xcode 27.1 iPhone Duo simulator (iOS 27.1 runtime, 2026-10-22) against a production React Native 0.83 app. Anything marked **(claim)** comes from a third-party write-up, not Apple. Measure it before you hardcode it.

## Device

| | Outer (closed) | Inner (open) |
|---|---|---|
| Diagonal | 5.4" | 7.6" |
| Points @3x | **466 × 678, measured** (1398 × 2034 px screenshot) | **951 × 669 upright, 669 × 951 rotated, measured** |
| Size class, portrait | compact W / regular H (same as every other iPhone) | regular W / regular H (same as iPad) |
| Size class, landscape | compact W / compact H | regular W / regular H |
| Portrait-only `UISupportedInterfaceOrientations` | honored; the screen stays portrait | honored by **letterboxing**: the app runs in a centered ~466-wide window with black bars (**measured**). Fix: `iphone-duo-adaptive-layout` → Native orientation |

- Announced 2026-09-09; ships 2026-10-23 on iOS 27.1.
- Split View on the inner display can make the window **any** width from roughly 300 to 951 pt, resized continuously. iPhone Mirroring on a Mac does the same.
- Fold, unfold, rotate and a Split View drag all **resize the live window**. Nothing relaunches. `useWindowDimensions()` re-renders on each of them. A `Dimensions.get('window')` at module scope is read once at launch and is wrong after the first fold.
- Safe-area insets are **asymmetric**. **Measured, closed portrait: `{ top: 0, right: 84, bottom: 34, left: 0 }`**. The status area moves to a right-hand column, so only 382 of the 466 pt are usable. A `SafeAreaView` whose `edges` include `'right'` honors this, and so do stack headers. A custom header that pads only `insets.top` puts its right-hand buttons inside the reserved column. The clock and status glyphs sit in that right-hand column (you won't see them if the app hides the status bar), so check against these numbers, not the picture.
- A height-based "has a notch" check (`height >= 812`, `react-native-iphone-x-helper`, …) is **false** on the closed Duo (678 pt tall), so the home-indicator padding is dropped. Derive it from the bottom inset instead.
- `Platform.isPad` is `false` on the Duo. `UIScreen.main` is ambiguous with two screens, and it is deprecated.
- `UIRequiresFullScreen = true` opts out of Split View, as on iPad, but the app **still resizes** on fold and unfold.
- Hinge and posture, `ReservedRegion` (`.division` = the fold, `.occlusion` = the camera) and vertical toolbars are iOS 27.1 native APIs with **no React Native binding**. Community modules exist (`@jusev/react-native-fold`, `react-native-foldable`); they are unverified.

## Build / SDK tiers

| Built with | On the inner display |
|---|---|
| iOS 26 SDK or older | runs in a centered iPhone-shaped window (letterboxed) |
| iOS 27 SDK | extends left of the status bar area |
| iOS 27.1 SDK | edge to edge; standard nav and toolbar buttons stack vertically |

**Measured: an app linked against the iOS 27 SDK without the UIScene lifecycle traps at launch** (`EXC_BREAKPOINT` in `__UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`). Adopt scenes (`UIApplicationSceneManifest` in Info.plist plus a `SceneDelegate` that creates `UIWindow(windowScene:)`) before the SDK bump; recipe in `native-ios.md`. Once scenes exist, URL-scheme and universal-link callbacks arrive on the scene delegate, not on `UIApplicationDelegate`, so forward them.

Check with `xcrun --sdk iphoneos --show-sdk-version`; you need `27.1`. **Measured:** Xcode 27 turns "deployment target below iOS 15" from a warning into a build error for every pod target, so clamp them in the Podfile `post_install`. The Duo simulator ships only with Xcode 27.1+. It can be installed next to your default Xcode (`/Applications/Xcode-27.1.app`) and selected per command with `DEVELOPER_DIR`. The iOS 27.1 runtime offers **only** the iPhone Duo device type. For a non-foldable iOS 27 control, use the 27.0 runtime.

## React Native ecosystem

- **CI, as of 2026-10-13:** GitHub's `macos-26` runner image ships Xcode 26.x and **no Xcode 27**. Xcode 27.x is on the separate `xcode-27-arm64` image label. Pointing `setup-xcode` at 27.1 on `macos-26` fails the job. Check `actions/runner-images` → `images/macos/macos-26-arm64-Readme.md` for the current state. EAS Build: pick an image with Xcode 27.1 once Expo publishes one.
- `react-native-screens` **4.30.0** is the iPhone Duo release: screens sit under an opaque nav bar on iOS 26+, the iOS 27 portrait header overlap is fixed, and there is a new `unstable_safeAreaEdges`. Its fixes apply to **native-stack** headers only (`@react-navigation/native-stack`, expo-router stacks). Versions 4.26.1+ require React Native 0.84+. Apps on the JS `@react-navigation/stack` gain nothing for the Duo from the bump.
- There is no React Native core fold or posture API yet (still an open PR). Width is the only cross-platform signal.
- `react-native-safe-area-context` reports the real asymmetric insets. Use `useSafeAreaInsets()` and apply each edge separately. The core RN `SafeAreaView` is iOS-only and legacy.
- In Split View a visible app can be `AppState === 'inactive'`. Pause media and timers on `'background'` only.
- **Expo:** the **SDK 58** prebuild template already adopts UIScene (`SceneDelegate: ExpoAppSceneDelegate`; checked on 58.0.17); SDK 57 does not. `app.json` `"orientation": "portrait"` writes the portrait lock into Info.plist, which letterboxes the inner display. **Measured:** a blank SDK 58 app plus the `withIphoneDuoOrientation` plugin, built with Xcode 27.1, fills 951×669 open and 669×951 rotated, and comes back portrait at 466×678 when folded while rotated.

## Simulator

- Xcode 27.1 → device type `com.apple.CoreSimulator.SimDeviceType.iPhone-Duo` on runtime `iOS-27-1`. The UI is **Device Hub** (`<Xcode 27.1>.app/Contents/Applications/DeviceHub.app`); Xcode 27 has no Simulator.app. The pose buttons are Closed, Partially Open, Open and Rotate Right (there is no Rotate Left).
- **Measured:** a freshly created sim boots open, and after a `shutdown`/`boot` it came back closed. Don't assume either; shoot both displays.
- There are two framebuffers. `xcrun simctl io <UDID> enumerate` lists them; the larger one (≈23 MB) is the inner display and the smaller (≈11.5 MB) is the outer. `simctl io screenshot --display=<UUID>` captures one of them. `simctl` has **no** fold or rotate commands.
- `xcrun simctl privacy grant` works on iOS 27.1, but tccd caches: grant before the app's first launch, or reboot the sim afterwards.
- **Split View cannot be reached on the 27.1 simulator** (there is no multitasking control, and synthesized touches never reach system UI). It needs hardware.
- Maestro drives the closed display. Inner-display hierarchy bounds come back skewed. Maestro's `takeScreenshot` returns a black frame.

## Sources

- Apple, "Prepare your app for iPhone Duo" tech talk: https://developer.apple.com/videos/play/tech-talks/111461/
- Apple, "Three steps to make your app shine on iPhone Duo": https://developer.apple.com/iphone-duo/prepare/
- Apple newsroom, 2026-09-09: https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/
- react-native-screens 4.30.0 release: https://github.com/software-mansion/react-native-screens/releases/tag/4.30.0
- React Native on iPhone Duo (third party): https://iphoneduosupport.com/frameworks/react-native/
- Simulator point sizes (third party): https://blakecrosley.com/blog/xcode-27-1-beta-iphone-duo-simulator
