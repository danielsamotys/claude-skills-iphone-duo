# Native iOS changes for iPhone Duo (bare React Native 0.78+ with `RCTReactNativeFactory`; Expo at the end)

There are three changes, in this order. The first two are needed before **any** build with the iOS 27 SDK. The third stops the inner display from being letterboxed. All of it was verified on the Xcode 27.1 Duo simulator in a production React Native 0.83 app. `<App>` is your target folder and `<ModuleName>` is the name passed to `AppRegistry.registerComponent`.

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

## 3. Orientation: portrait on phones, everything on the inner display

`Info.plist`: list all four orientations under `UISupportedInterfaceOrientations` and delete `UIRequiresFullScreen`. An app that is not full screen must list all orientations, or App Store validation fails.

`AppDelegate.swift`:

```swift
func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
  window?.traitCollection.horizontalSizeClass == .regular ? .all : .portrait
}
```

Compact width (every phone and the closed Duo) stays portrait, exactly as before. Only the inner display and iPad rotate. The `registerForTraitChanges` block in step 2 is **required**. Without it, UIKit keeps its last answer across a fold: fold while the inner display is rotated, and the phone-size display comes up in landscape (**measured**).

There is no JS change. Screens keep branching on width, never on orientation.

## Expo (Continuous Native Generation)

Hand edits to `ios/` are lost on the next prebuild, so everything goes through `app.json` and config plugins.

1. **UIScene:** upgrade to **Expo SDK 58+**. Its template ships `SceneDelegate: ExpoAppSceneDelegate` and creates the window there. Don't hand-write a scene plugin for an older SDK.
2. **Pod clamp:** needed only if the readiness audit counts pods below iOS 15. Add it with a `withPodfile` mod inside `post_install`, after the existing calls.
3. **Orientation:** copy `../templates/withIphoneDuoOrientation.js` to `plugins/` and add `"./plugins/withIphoneDuoOrientation"` to `app.json` `plugins`. It writes all four orientations, overrides `application(_:supportedInterfaceOrientationsFor:)` in the AppDelegate (the module name stays `"main"`), and adds the trait-change re-query to the SceneDelegate. It throws if the SDK 58 template anchors are missing. It doesn't touch Android, so keep `"orientation": "portrait"` if Android phones must stay portrait. (Android 16 ignores orientation locks on large screens anyway.)

Verified: blank SDK 58.0.17 app, `expo prebuild` run twice (the plugin is idempotent), Release build with Xcode 27.1, Duo simulator: 466×678 closed, 951×669 open, 669×951 rotated, and portrait again after folding while rotated.
