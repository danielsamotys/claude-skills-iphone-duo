# Native iOS changes for iPhone Duo (bare React Native 0.78+ with `RCTReactNativeFactory`; Expo at the end)

There are three changes, in this order. The first two are needed before **any** build with the iOS 27 SDK. The third stops the inner display from being letterboxed and is usually one deleted Info.plist key. All of it was verified on the Xcode 27.1 Duo simulator in a production React Native 0.83 app. `<App>` is your target folder and `<ModuleName>` is the name passed to `AppRegistry.registerComponent`.

## 1. Pod deployment targets (`ios/Podfile`, inside `post_install`)

```ruby
installer.pods_project.targets.each do |target|
  target.build_configurations.each do |bc|
    dt = bc.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
    bc.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.1' if dt && dt.to_f < 15.1
  end
end
```

Xcode 27 fails the build for any pod target below iOS 15. Don't edit `Pods/` by hand.

## 2. UIScene lifecycle (required by the iOS 27 SDK; without it the app traps at launch)

`<App>/Info.plist`:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key>
  <dict>
    <key>UIWindowSceneSessionRoleApplication</key>
    <array><dict>
      <key>UISceneConfigurationName</key><string>Default Configuration</string>
      <key>UISceneDelegateClassName</key><string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
    </dict></array>
  </dict>
</dict>
```

`AppDelegate.swift`: keep creating the factory in `didFinishLaunching`, but stop creating the window and starting React there. Store the launch options for the scene:

```swift
var launchOptions: [UIApplication.LaunchOptionsKey: Any]?
// in application(_:didFinishLaunchingWithOptions:), replace
//   window = UIWindow(frame: UIScreen.main.bounds); factory.startReactNative(withModuleName:in:launchOptions:)
// with
self.launchOptions = launchOptions
```

`<App>/SceneDelegate.swift`. Add it to the app target; a file that exists only on disk is not compiled:

```swift
import UIKit
import React

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var appDelegate: AppDelegate? { UIApplication.shared.delegate as? AppDelegate }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene, let appDelegate else { return }
    let window = UIWindow(windowScene: windowScene)
    appDelegate.reactNativeFactory?.startReactNative(withModuleName: "<ModuleName>", in: window, launchOptions: appDelegate.launchOptions)
    self.window = window
    appDelegate.window = window

    // Fold/unfold changes the size class without a rotation, so make UIKit re-ask for the orientation mask (step 3).
    if #available(iOS 17.0, *), let root = window.rootViewController {
      root.registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (vc: UIViewController, _: UITraitCollection) in
        vc.setNeedsUpdateOfSupportedInterfaceOrientations()
      }
    }
    for context in connectionOptions.urlContexts { handle(url: context.url) }
    for activity in connectionOptions.userActivities { handle(userActivity: activity) }
  }

  // With scenes, deep links and universal links arrive here, not on the app delegate.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) { URLContexts.forEach { handle(url: $0.url) } }
  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) { handle(userActivity: userActivity) }

  private func handle(url: URL) { _ = appDelegate?.application(UIApplication.shared, open: url, options: [:]) }
  private func handle(userActivity: NSUserActivity) {
    _ = appDelegate?.application(UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
  }
}
```

If your AppDelegate has no `application(_:open:options:)` or `application(_:continue:restorationHandler:)`, call `RCTLinkingManager` directly instead.

Smoke test: the app launches, a deep link opens the right screen, and a universal link opens the right screen.

## 3. Orientation: delete `UIRequiresFullScreen`, keep the portrait list

On the iOS 27.1 Duo simulator (**measured**), an app that supports multitasking fills the inner display whatever `UISupportedInterfaceOrientations` says, and the closed display still honors the portrait lock. Only `UIRequiresFullScreen = true` keeps the lock on the inner display, and that letterboxes the Open pose. So the fix is one Info.plist change: delete `UIRequiresFullScreen` (or set it to `false`). Keep the orientation list as it is.

If the app also targets iPad, App Store validation wants all four orientations for iPad when the app doesn't require full screen. List them under `UISupportedInterfaceOrientations~ipad`, not in the base key, so phones stay portrait.

**Only if your base key already lists landscape** and phones must still stay portrait, add a size-class gate in `AppDelegate.swift` and keep the `registerForTraitChanges` block from step 2. Without that block UIKit keeps its last answer across a fold, and the closed display came up in landscape after folding while rotated (**measured**):

```swift
func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
  window?.traitCollection.horizontalSizeClass == .regular ? .all : .portrait
}
```

There is no JS change. Screens keep branching on width, never on orientation.

## Expo (Continuous Native Generation)

Hand edits to `ios/` are lost on the next prebuild, so everything goes through `app.json` and config plugins.

1. **UIScene:** upgrade to **Expo SDK 58+**. Its template ships `SceneDelegate: ExpoAppSceneDelegate` and creates the window there. Don't hand-write a scene plugin for an older SDK.
2. **Pod clamp:** needed only if the readiness audit counts pods below iOS 15. Add it with a `withPodfile` mod inside `post_install`, after the existing calls.
3. **Orientation:** make sure `ios.requireFullScreen` is unset or `false` (Expo's default). Keep `"orientation": "portrait"`. Nothing else is needed.

Verified: blank SDK 58.0.17 app, Release build with Xcode 27.1, Duo simulator. With the defaults it is 466×678 closed, 951×669 open and 669×951 rotated, and portrait again after folding while rotated. With `requireFullScreen: true` the Open pose is letterboxed.
