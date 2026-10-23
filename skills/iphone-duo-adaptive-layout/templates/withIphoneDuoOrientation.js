// Expo config plugin: portrait on phones and the closed iPhone Duo, every orientation on the Duo's inner display and iPad.
// Needs Expo SDK 58+, whose prebuild template already adopts UIScene (SceneDelegate.swift). Android is untouched, so
// app.json can keep "orientation": "portrait" for Android phones.
// Use: copy into your app (e.g. plugins/withIphoneDuoOrientation.js) and add "./plugins/withIphoneDuoOrientation" to app.json "plugins".
const fs = require('fs')
const path = require('path')
const { withInfoPlist, withAppDelegate, withDangerousMod } = require('expo/config-plugins')

const MARK = 'iphone-duo:'
const ORIENTATIONS = [
  'UIInterfaceOrientationPortrait',
  'UIInterfaceOrientationPortraitUpsideDown',
  'UIInterfaceOrientationLandscapeLeft',
  'UIInterfaceOrientationLandscapeRight',
]
const APP_DELEGATE = `
  // ${MARK} portrait on compact width (phones, closed Duo); every orientation on regular width (Duo inner display, iPad).
  public override func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    window?.traitCollection.horizontalSizeClass == .regular ? .all : .portrait
  }
`
const SCENE_DELEGATE = `
  // ${MARK} folding changes the size class without a rotation, so make UIKit re-ask AppDelegate for the orientation mask.
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if #available(iOS 17.0, *), let root = window?.rootViewController {
      root.registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (vc: UIViewController, _: UITraitCollection) in
        vc.setNeedsUpdateOfSupportedInterfaceOrientations()
      }
    }
  }
`
const fail = (what) => {
  throw new Error(`withIphoneDuoOrientation: ${what} not found. Expo SDK 58+ prebuild template expected.`)
}

module.exports = function withIphoneDuoOrientation(config) {
  // All four orientations so the window can resize instead of being letterboxed; an app that isn't full screen must list them all.
  config = withInfoPlist(config, (c) => {
    c.modResults.UISupportedInterfaceOrientations = ORIENTATIONS
    delete c.modResults.UIRequiresFullScreen
    return c
  })
  config = withAppDelegate(config, (c) => {
    const src = c.modResults.contents
    if (src.includes(MARK)) return c
    const anchor = /var reactNativeFactory: RCTReactNativeFactory\?\n/
    if (!anchor.test(src)) fail('AppDelegate anchor')
    c.modResults.contents = src.replace(anchor, (m) => m + APP_DELEGATE)
    return c
  })
  return withDangerousMod(config, [
    'ios',
    (c) => {
      const file = path.join(c.modRequest.platformProjectRoot, c.modRequest.projectName, 'SceneDelegate.swift')
      if (!fs.existsSync(file)) fail('SceneDelegate.swift')
      let src = fs.readFileSync(file, 'utf8')
      if (src.includes(MARK)) return c
      const anchor = '// Extension point for config plugins.\n'
      if (!src.includes(anchor)) fail('SceneDelegate anchor')
      src = src.replace(anchor, (m) => m + SCENE_DELEGATE)
      if (!/^import UIKit$/m.test(src)) src = `import UIKit\n${src}`
      fs.writeFileSync(file, src)
      return c
    },
  ])
}
