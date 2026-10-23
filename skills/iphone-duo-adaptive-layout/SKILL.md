---
name: iphone-duo-adaptive-layout
description: Use when a React Native screen, style, safe-area padding, modal, bottom sheet, carousel, drawer or AppState handler must work on iPhone Duo (Apple's foldable), in Split View, or in any window that resizes at runtime. Typical asks are "X looks stretched/clipped/cut off on the foldable", "make X work on iPhone Duo", "replace Dimensions.get", "drawer on the big inner screen", "app is letterboxed / black bars on the unfolded screen", a file flagged by iphone-duo-readiness, or questions about hinge, posture or reserved-region APIs in React Native.
---

# Adaptive layout for iPhone Duo (React Native)

**Core rule: the window is a live value, never a constant.** On the Duo it changes width on fold, unfold, rotate and Split View, with no relaunch. Anything computed once from `Dimensions.get()` is wrong after the first fold. Read `references/iphone-duo-facts.md` (sizes, insets, SDK, sources) before touching code.

Assumes `react-native-safe-area-context` (a `SafeAreaProvider` at the root) and works with React Navigation or expo-router. Paths below are examples. Look for your app's equivalent first.

## The one shared primitive

Search for an existing window/breakpoint hook first (`useWindowLayout`, `useBreakpoint`, `useResponsive`). If none exists, create one in your hooks folder (in a monorepo, in the shared UI package so every feature package can use it). Never add a second breakpoint anywhere else.

```ts
import { useWindowDimensions } from 'react-native'

// RN's stand-in for Apple's "regular" horizontal size class: Duo's inner display (≈669pt) is wide,
// every closed phone (≤466pt) and half a Split View is not.
export const WIDE_BREAKPOINT = 600

export const useWindowLayout = () => {
  const { width, height } = useWindowDimensions()
  return { width, height, isWide: width >= WIDE_BREAKPOINT }
}
```

Put one test beside it. Drive the real hook through `Dimensions.set`: on RN 0.83 (where this was verified), `jest.spyOn(RN, 'useWindowDimensions')` does **not** intercept the getter export.

```ts
const setWidth = (width: number) =>
  act(() => Dimensions.set({ window: { width, height: 800, scale: 3, fontScale: 1 } }))
const { result } = renderHook(() => useWindowLayout())
setWidth(390); expect(result.current.isWide).toBe(false)
setWidth(669); expect(result.current.isWide).toBe(true)   // same mount: proves the live re-render
```

## Fixing a stale size read: decide in this order

| # | If the value… | Do this | Example |
|---|---|---|---|
| 1 | can be expressed by layout | `flex: 1`, `'100%'`, `aspectRatio`, `alignSelf: 'stretch'`, `StyleSheet.absoluteFillObject`, a **flex ratio** for "N% of the window", or `onLayout` of the parent. For the flex ratio, `marginTop: height * 0.45` becomes a spacer with `flex: 45` plus a sheet with `flex: 55`. Yoga resolves `%` margin and padding against *width*, so never use those | full-screen photo, modal backdrop, camera preview, bottom-sheet height |
| 2 | is really fixed (sized against a fixed-height row or a design constant) | a named constant | thumbnail inside an 80 pt card |
| 3 | genuinely tracks the window and no layout can express it (carousel page width, paging or parallax offsets, snap points passed to a library) | `const { width, height } = useWindowLayout()` **inside the component**; derive with `useMemo`; pass as an inline style or a library prop | `ITEM_WIDTH`, `PARALLAX_OFFSET`, `snapPoints` |
| 4 | is used by several keys of a `styles.ts` | turn the file into a style hook memoized on the size: `export const useStyles = () => { const { width } = useWindowDimensions(); return useMemo(() => StyleSheet.create({ … }), [width]) }`. Consumers call `useStyles()` inside the component. Size from `width`; for a wide/compact branch use `useWindowLayout().isWide`, never a new threshold | a bottom sheet's `styles.ts` |

**Paged lists keep their old offset after a resize.** `useWindowDimensions` fixes the page width, but a paged `FlatList` or `ScrollView` lands between pages after a fold. Re-snap on width change: `useEffect(() => { listRef.current?.scrollToIndex({ index, animated: false }) }, [width])`.

Never use `Dimensions.addEventListener`; the hook already re-renders. Never use `Dimensions.get('screen')`: that is the display, not your window, and in Split View they differ.

Resize regression test (one per pattern, not one per file): render the style hook with `renderHook`, run `act(() => Dimensions.set({ window: d, screen: d }))` going from 466×678 to 669×951, and assert the sized value follows. Check that the test fails when the memo deps are frozen.

## Wide layout (`isWide`): only these, unless a design says otherwise

- **Reading content** (anything that reads as one vertical stack of text, cards, form fields or list rows: chat, forms, articles, settings, card dashboards): wrap the content **and its input toolbar** in one column with `{ width: '100%', maxWidth: WIDE_BREAKPOINT, alignSelf: 'center' }`, adding `flex: 1` on a `View` or `flexGrow: 1` on a `ScrollView`'s `contentContainerStyle` only when the content must fill the height (`flex: 1` there stops scrolling). Put the column on the node that carries the horizontal padding, so the 600 cap includes it. If the app has a shared screen wrapper, put the column there once, then grep for screens that bypass the wrapper (raw `SafeAreaView`) and give each its own column. Maps, full-bleed media, camera views and immersive single-purpose screens (a timer, a counter, a player) stay full width. Full-screen overlays, modals and loaders stay outside the column so they still cover the window. A modal's own reading content goes in a column inside the modal.
- **Drawer** (React Navigation): set `drawerType: isWide ? 'permanent' : undefined` in the drawer's `screenOptions`. `undefined` keeps the library default. This is usually the highest-leverage single change.
- **Tile grids only** (photo thumbnails, square cards): `numColumns={isWide ? 2 : 1}` with a `key` that includes the column count, because FlatList can't change `numColumns` in place. Full-width table rows stay single-column; they read fine at 669 pt. Grids that already lay out in fixed columns stay as they are.
- **Tabs** (React Navigation, expo-router, native tabs): leave them alone. Whether iOS 27.1 stacks a native tab bar vertically on its own is not verified here.
- Do **not** build master-detail or two-pane screens, sidebars or tab rails without a design. Do **not** branch on `Platform.isPad` (false on the Duo), on orientation, or on device model.

## Safe area: each edge on its own

Use `useSafeAreaInsets()` and apply `top`, `bottom`, `left` and `right` separately. **Closed portrait measures `{ top: 0, right: 84, bottom: 34, left: 0 }`**, so 382 of the 466 pt are usable. Screens inside `SafeAreaView edges={[…'right']}` and stack headers already handle this. The usual misses:

- **Shared screen wrapper** (`Screen`, `Container`) whose default `edges` omit `'right'`: add `'left', 'right'` to the default once. Side insets are 0 on every other iPhone, so nothing else changes. In a monorepo, every app using the wrapper gets the fix; list the sibling apps in the PR.
- **Custom absolute headers:** add `paddingLeft: insets.left` and `paddingRight: insets.right` next to the `paddingTop`.
- **Edge-to-edge scroll content:** put side insets on `contentContainerStyle`. Horizontal carousels inside it still scroll.
- **A shared modal wrapper:** pad the side insets there once, for every caller. **Trap (`react-native-modal` ≤ 13 with `avoidKeyboard`):** the library applies `style` to **two nested views**, so padding passed in `style` counts twice. Give each view half the inset (`paddingRight: right / 2`) and pin the total in a test that sums `paddingRight` over the rendered host nodes. In a modal:
  - top and bottom insets go in the content container or on a view inside the content (applied once), never in `style`;
  - on a full-screen modal the side insets show the backdrop; paint the strip with `style={{ backgroundColor: <sheet colour> }}` (a colour can't double; not yet checked on the sim) and keep content out of it;
  - a scrolling body needs `propagateSwipe` to keep swipe-to-close, or no `swipeDirection` at all. Otherwise the swipe gesture competes with the scroll.
- **"Has a home indicator" helpers** (`isIphoneX`, `hasNotch`, `height >= 812`): fix the **definition**, not every consumer: `Platform.OS === 'ios' && (initialWindowMetrics?.insets.bottom ?? 0) > 0`, from `react-native-safe-area-context`. That keeps every phone identical and makes the closed Duo (678 pt tall) correct. The library's jest mock reports zero insets, so give the mocked `initialWindowMetrics` a bottom inset of 34, or every footer snapshot flips.
- Replacing an `isIphoneX ? N : M` in a **shared component** → `Math.max(insets.bottom, M)`. That stays within a few points of today and doesn't double-pad under a parent `SafeAreaView`. In new code or a single screen, use `insets.bottom + M` (M = the design's padding, 16 if none). Never mirror one side onto the other, and never import `SafeAreaView` from `'react-native'`.

## Native orientation: unlock the inner display, keep phones portrait

A portrait-only app is letterboxed on the unfolded display (a centered ~466-wide window with black bars), and an app built with an SDK older than iOS 27.1 is letterboxed regardless. 

- **Bare React Native:** follow `references/native-ios.md`: (1) pod deployment-target clamp, (2) UIScene adoption (an iOS 27 SDK build traps at launch without it), (3) all orientations in Info.plist, with a size-class gate in AppDelegate and a trait-change re-query in SceneDelegate.
- **Expo:** upgrade to SDK 58+ (its template already adopts UIScene). Staying on SDK ≤ 57 means no iOS 27 SDK build, so the inner display stays letterboxed; the JS fixes still help the closed display and Split View. Then copy `templates/withIphoneDuoOrientation.js` into the app and add it to `app.json` `plugins`. It does step 3 and leaves Android alone, so `"orientation": "portrait"` keeps Android phones locked.

No orientation library and no JS orientation code.

## AppState: `inactive` is not hidden

In Split View the app without focus is **visible** and `inactive`. Pause cameras, timers, polling and media on `'background'` only, and resume on `'active'`. Fix shared hooks (foreground/interval/polling helpers) once. React Query: `focusManager.setFocused(state !== 'background')`, not `state === 'active'`, or `refetchInterval` polling stops in a visible Split View app. A per-screen `nextAppState === 'active'` gate for *resuming* is fine; a `!== 'active'` gate for *pausing* is the bug.

## Done when

- The readiness audit (`iphone-duo-readiness`) no longer lists the touched files.
- Type-check, lint and the touched tests pass.
- Then hand off to `iphone-duo-verify` for the simulator pass.

Don't name `Dimensions.get` or `isIphoneX` in new comments: the audit greps tokens.

## Common mistakes

| Mistake | Fix |
|---|---|
| Hardcoding 466 / 669 / 951 anywhere | Only `WIDE_BREAKPOINT`; everything else comes from the hook at render time |
| A new `maxWidth: 480` / `520` / … per screen | `WIDE_BREAKPOINT`. Existing caps on a fixed-column grid or design element are design constants (rung 2); leave them |
| `StyleSheet.create` inside the component body, rebuilt every render | A style hook with `useMemo(…, [width])` (rung 4) |
| A long list as `ScrollView` + `.map` | Hundreds of rows block JS for tens of seconds, so a fold looks "missed". Use `FlatList` (measured: 360 rows, 35 s → 1.5 s) |
| Padding a `react-native-modal` through `style` and expecting it once | With `avoidKeyboard` it is applied twice; see the modal trap above |
| `useWindowDimensions` at module scope | Hooks run in components. Module scope is frozen |
| "Fixing" it by locking orientation natively | A lock letterboxes the inner display. Unlock it per `native-ios.md`; branch on width in JS |
| Treating iPad support (`TARGETED_DEVICE_FAMILY`, `supportsTablet`) as Duo support | The Duo is an iPhone; the iPad flag changes nothing for it |
