# Sample: iPhone Duo readiness report

This is real output from the `iphone-duo-readiness` skill, run on the open-source Bluesky app ([bluesky-social/social-app](https://github.com/bluesky-social/social-app) at commit `dc2a0c1`, Expo SDK 58, React Native 0.88) on 2026-10-23. It shows what the skill produces; it is not a bug report against Bluesky. `ios/` is not checked in (Continuous Native Generation) and prebuild was not run, so sections 1 and 3 come from `app.config.js`, `package.json` and CI config.

---

**1. Build blocker.** Local default Xcode is 26.6 (iOS 26.5 SDK). Xcode 27.1 with the 27.1 SDK is installed side by side, and the Duo simulator exists. CI pins `xcode-version: "26.4"` on `macos-26` / `macos-26-xlarge`. Any CI build is iOS 26 SDK, so it is letterboxed on the inner display. The EAS profile pins no `image`, so it uses Expo's default image, whose Xcode must reach 27.1. **UIScene:** Expo SDK 58's prebuild template already adopts it, so there's nothing to add. The pod deployment-target count can't be read without a prebuilt `ios/`.

**2. Dependencies.** `react-native-screens` 4.30.0 is already the Duo release, and the app uses 10 `createNativeStackNavigator` stacks, so the native-stack header fixes apply. No `react-native-modal` + `avoidKeyboard` usage.

**3. Native config.** `app.config.js` sets no `requireFullScreen`, so Expo's default (`false`) applies. Once the app is built with the 27.1 SDK, the inner display fills the window instead of letterboxing. The lightbox locks portrait at runtime with `expo-screen-orientation` (`src/components/Lightbox/pager/ImagePager.tsx:223-226`); check on the simulator that opening it on the inner display doesn't letterbox. Don't add `requireFullScreen`. `supportsTablet: true`.

**4. Stale size reads.** No module-scope `Dimensions.get`, and 53 `useWindowDimensions` call sites. The script counts 9 `Dimensions.get('window')` reads. Three are fine:
- `src/alf/breakpoints.native.ts:18` feeds `useSyncExternalStore` with a `Dimensions` change listener.
- `src/alf/util/dimensions.ts:9` is an initial state value.
- `src/components/ContextMenu/index.tsx:240` deliberately handles resizes.

The other six read the window during render without subscribing, so they keep the old value after a fold until something else re-renders them:
- **List minimum heights:** `src/view/com/posts/PostFeed.tsx:1158`, `src/features/followingV2/home/PostFeed.tsx:1457`, `src/view/com/lists/ListMembers.tsx:288` and `src/view/com/posts/FollowingEndOfFeed.tsx:38` use `height * 1.5` / `* 0.75`.
- **Overlay offset:** `src/ageAssurance/components/RedirectOverlay.tsx:157`.
- **Embed player:** `src/lib/strings/embed-player.ts:608` branches on `height < 600`.

Pattern for all of them: read `useWindowDimensions()` in the component, or use the flex/`onLayout` rungs. The 3 `Dimensions.addEventListener` uses are deliberate resize handling (breakpoints, context menu); keep them.

**5. Device heuristics and side insets.** `IS_IPAD = Platform.isPad` (`src/env/index.ts:47`) is false on the Duo, so anything gated on it stays in phone layout on the inner display. Branch on width instead. The `isTablet*` hits are web media queries; ignore them. 21 files pad a top inset with no right inset. Shared ones first:
- `src/view/shell/index.tsx:106` pads the whole shell with `insets.top`/`insets.bottom` only.
- `src/view/com/home/HomeHeaderLayoutMobile.tsx:52` pads `insets.top` on a header whose feed-settings button sits on the right.
- `src/screens/Profile/Header/index.tsx:188` pads `insets.top` only; check its right-hand controls.

On the closed Duo (`right: 84`) those controls sit under the status column. Add `paddingLeft/Right` from the insets.

**6. AppState.** Several *pause* gates treat `inactive` as hidden, so feeds and chat stop updating in a visible Split View window:
- `src/state/queries/post-feed.ts:389`
- `src/state/queries/notifications/unread.tsx:167`
- `src/features/followingV2/home/queries/postFeed.ts:1157` (`AppState.currentState !== 'active'`)
- `src/screens/Messages/ChatList.tsx:142` and `Inbox.tsx:128` (`isActive = state === 'active'`)
- `src/screens/VideoFeed/index.tsx:655-660` (watch-time tracking stops in Split View)

Gates that only *resume* on `'active'` are fine (`PostFeed.tsx:575`, `messages/events/index.tsx:73`).

**7. Offsets by size class.** No hardcoded `keyboardVerticalOffset`.

**Verified OK.** No module-scope size reads, no core `SafeAreaView`, no symmetric inset math beyond `Math.max(insets.bottom, …)` floors (fine).

**Suggested order.**
1. CI to Xcode 27.1 and the EAS image; confirm the Info.plist orientations after prebuild.
2. The shell and header side insets (one shared fix covers most screens).
3. The AppState pause gates in the shared query hooks, then the screens.
4. The render-time `Dimensions.get` reads (list minimum heights first) and the `Platform.isPad` gate.
