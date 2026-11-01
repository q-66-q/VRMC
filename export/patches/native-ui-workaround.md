# Native UI workaround attempt (M3-W1) — source-level notes

Local refbuild changes (not yet consolidated into the repo patch file):

1. `Natives/SceneDelegate.m` — append to `Documents/native-ui.log`:
   - `willConnect` window scene bounds / role / activation state,
   - after `makeKeyAndVisible`: window frame, rootVC class, hidden/alpha,
   - t+1.5 s: rootVC.view class/frame/subview count, force layout.
   Evidence showed a valid 1280×720 scene and split-view hierarchy but blank content (EV-0076).

2. `Natives/ios_uikit_bridge.m` — native root-VC workaround:
   - `vrmc_runsOnVisionDevice()` checks `Info.plist VRMCNativeBuild` (set only on the native app),
     then `UIDevice.userInterfaceIdiom == 6`, then `sysctl hw.model`.
   - When true: `window.rootViewController = LauncherNavigationController(root: LauncherProfilesViewController)`
     instead of `LauncherSplitViewController` (EV-0078). The branch executes but the app crashes in
     `-[LauncherProfilesViewController viewWillAppear:]`:
     `@[sidebarViewController drawAccountButton, self.createButtonItem]` where
     `sidebarViewController` is a macro over `self.splitViewController.viewControllers[0]` → nil →
     `NSArray` exception. So a plain navigation root is not sufficient.

3. `Natives/LauncherNavigationController.m` — prototype auto-launch hook (local only):
   - if the env var `VRMC_NATIVE_AUTOLAUNCH` is set, auto-call `launchMinecraft:` at +10 s / +40 s.
   - Used with `Documents/autolaunch.flag` earlier to prove gate 3 (EV-0077). Not for shipping.

Next engineering step: a native-specific UI shell (SwiftUI/UIKit) that either hosts a plain launcher
menu or calls `launchMinecraft:` directly, without instantiating view controllers that require
`self.splitViewController`. Alternatively provide a split-view shim that satisfies the sidebar macros.
