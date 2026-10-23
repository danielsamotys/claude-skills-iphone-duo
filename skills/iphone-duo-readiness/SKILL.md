---
name: iphone-duo-readiness
description: Use when asked whether a React Native or Expo app as a whole is ready for iPhone Duo (Apple's foldable), to audit for foldable / Split View / resizable-window problems, or before planning Duo work. Typical asks are "is the app Duo-ready", "audit for iPhone Duo", "what breaks on the foldable", "foldable readiness report". It is whole-app and read-only. For one known screen, use iphone-duo-adaptive-layout instead.
---

# iPhone Duo readiness audit

One-shot and read-only. The Duo turns the window into something that **resizes at runtime** (fold, unfold, rotate, Split View) and reserves a side column when folded. The audit finds every place that assumed neither happens. Afterwards, fix with `iphone-duo-adaptive-layout` and test with `iphone-duo-verify`.

Don't re-derive facts from memory: read `../iphone-duo-adaptive-layout/references/iphone-duo-facts.md` first.

## Run

From this skill's base directory, pointing at the app (the folder with `package.json`; in a monorepo, the app package):

```bash
bash scripts/audit.sh /path/to/app [shared-src-dir ...]   # monorepo: add the shared UI packages the app renders
```

It scans whichever of `src app components lib screens features modules hooks navigation` exist, plus any extra dirs. Expo with CNG (gitignored `ios/`): sections 1 and 3 read the prebuilt `ios/`. If it is missing, or the script warns it is older than `app.json`, ask before running `npx expo prebuild -p ios --no-install`, or report those sections from `app.json` and the Expo SDK version alone.

Script section → report item: 1→1, 2→2, 3→3, 4→4, 5→5, 8→6, 9→7. Script sections 6 and 7 (JS orientation, symmetric insets) go under **Verified OK** when empty; section 7's "insets.top but no side inset" list goes to item 5. Section 4 prints the first offending expression per file, so you can classify without opening the file. Open a file only to judge impact. Don't re-grep by hand; if you find a pattern the script misses, say so in the report.

## Report (this exact shape, in this order)

**1. Build blocker.** Local SDK, CI and EAS SDK versus 27.1. Below 27.1 the app runs letterboxed on the inner display no matter what the JS does. State the versions found and whether the Duo simulator exists locally. This is always item 1, even when everything else is clean. Report the two hard prerequisites for the SDK 27 rebuild here as well:
- **UIScene lifecycle** (manifest plus `SceneDelegate`). Without it, every iOS 27 SDK build traps at launch.
- **Pod deployment targets ≥ 15.** Xcode 27 errors on anything lower; a Podfile `post_install` clamp handles it.

Report the pod clamp only when the script counts offending pods. Recipe: `../iphone-duo-adaptive-layout/references/native-ios.md`. **Expo:** SDK 58+ already adopts UIScene, so for SDK ≤ 57 the fix is the SDK upgrade, not a hand-written SceneDelegate. EAS with no `image` pinned uses Expo's default image: say its Xcode version must reach 27.1. No macOS CI means builds are local or EAS; say which.

**2. Dependencies.** A `react-native-screens` version below 4.30.0 matters only if the app shows native-stack headers (`createNativeStackNavigator` or expo-router `<Stack>` with headers that are not all `headerShown: false`; the audit prints both counts). With a JS stack only, it is not a Duo blocker. Versions 4.26.1+ need React Native 0.84+, so the bump may imply an RN upgrade. Report the `react-native-modal` + `avoidKeyboard` count as a heads-up for the double-padding trap.

**3. Native config.** Report `UIRequiresFullScreen`, the orientations and `UIScreen.main` as found (for Expo, also `app.json` `orientation`), with their *measured* meaning:
- `UIRequiresFullScreen` opts the app out of Split View, but the app **still resizes** on fold and unfold.
- `UIRequiresFullScreen = true` (Expo: `ios.requireFullScreen: true`) **letterboxes** the Open and Partially Open poses into a phone-shaped window with black bars. That is the first thing a Duo owner sees, so rank it right after the blocker; the fix is deleting the key.
- A portrait-only orientation list on its own is **not** a finding: the inner display ignores it for apps that support multitasking (measured), and phones stay portrait.
- `UIScreen.main.bounds` in the AppDelegate goes away with UIScene adoption.
- For Expo with CNG, every native fix is `app.json` or a config plugin.

Never recommend a stronger lock or full screen.

**4. Stale size reads.** The `Dimensions.get` list, grouped by what the user sees: full-screen media, camera or crop; bottom sheets and modals positioned by height; carousels and paging by width; card and thumbnail grids. Call out `Dimensions.get('screen')` separately (it is the display, not the window). Give the count and the fix pattern once, not per file.

**5. Device heuristics and side insets.** If a "has a notch" helper is a height check, report its **definition** as one finding (false on the closed Duo; fix the definition), not each consumer. From the "top inset without a right inset" list, report a shared screen wrapper (`Screen`, `Container`, `Layout`) first, as one fix. Then report only files that put controls near the right edge. The closed Duo reserves `right: 84`.

**6. AppState.** Every `'active'` gate that would pause a *visible* Split View app (`inactive` ≠ hidden), including React Query's `focusManager.setFocused(state === 'active')`, which stops `refetchInterval` polling. Name shared hooks before per-screen code. Drop false positives such as `status === 'active'` on data.

**7. Offsets by size class.** Hardcoded `keyboardVerticalOffset` and fixed header heights.

**Verified OK.** One line listing what the script found nothing for.

**Suggested order.** Three to five lines:
1. Blocker and dependencies first.
2. Then shared definitions (notch helper, AppState hooks, the shared modal and bottom sheet); one fix each covers many consumers.
3. Then the per-file size reads, which are independent of each other.
4. Then offsets and the `UIRequiresFullScreen` decision.

Format: `file:line` references, one fix pattern per group, under ~700 words. No code block longer than 5 lines; the fix recipes live in `iphone-duo-adaptive-layout`.

## Out of scope (do not recommend)

- `react-native-orientation-locker`, `expo-screen-orientation` locks, or any JS orientation code. In JS, branch on width.
- Hinge-angle, `ReservedRegion` or posture native modules: there is no RN binding. They are only worth it after everything above is fixed and there is a product need.
- iPad flags (`TARGETED_DEVICE_FAMILY`, `supportsTablet`): the Duo is an iPhone.

## Common mistakes

| Mistake | Reality |
|---|---|
| "CI is on Xcode 26.x, the SDK is fine" | You need **27.1**. Anything older is letterboxed. It is always the first line |
| Calling UIScene adoption "unrelated to Duo, separate ticket" | It gates the SDK 27 rebuild, which gates everything else. It belongs in item 1 |
| "Bump react-native-screens to 4.30 for Duo" | Only if native-stack is used, and check the RN 0.84+ requirement first |
| Ranking a portrait-only orientation list as the letterbox cause | Measured: only `UIRequiresFullScreen` (or an old SDK) letterboxes. A portrait list is fine |
| Ranking JS orientation checks as the #1 problem | JS `isLandscape` branches are a minor item, not a blocker |
| Treating `inactive` as "app hidden" | In Split View the other app has focus; yours is visible and `inactive` |
| Auditing by hand with ad-hoc greps | Run the script; it is the checklist |
