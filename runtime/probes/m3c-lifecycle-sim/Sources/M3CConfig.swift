import Foundation

/// Diagnostic configuration, all selectable with launch arguments (NSArgumentDomain), e.g.
///   xcrun simctl launch <udid> dev.vrmc.m3c -M3CPark hidden -M3CParkWhen firstframe
///
///   M3CPark        hidden | alpha | tinyalpha | contentalpha | contenthidden | none
///                  hidden       = window.isHidden=true AND window.alpha=0 (what Shell.swift does today)
///                  alpha        = window.alpha=0 only (window stays in the hierarchy)
///                  tinyalpha    = window.alpha=0.01 (near-invisible but non-zero)
///                  contentalpha = window left visible, root view alpha=0 (content invisible, chrome stays)
///                  contenthidden= window left visible, root view hidden
///                  none         = do not touch the windows (control)
///   M3CParkWhen    open | firstframe        (park right after openImmersiveSpace returns, or only
///                                            after the first compositor frame is presented)
///   M3CParkScope   all | main               (which windowApplication scenes to park)
///   M3COpenDelay   seconds before the auto open (0 = "at launch")
///   M3CSecondWindow 1 = open a second WindowGroup (id "second") and keep it visible, to separate
///                       "window scene deactivated" from "app backgrounded"
///   M3CRestoreAfter seconds after parking to restore the windows (<0 = never)
///   M3CReopen      1 = dismiss the immersive space after M3CReopenAfter s and open it again
///   M3CReopenAfter seconds after parking before the dismiss/reopen test
///   M3CAutoOpen    0 = never open the immersive space (control)
///   M3CTag         free-form label echoed into the log
struct M3CConfig {
    var park: String
    var parkWhen: String
    var parkScope: String
    var openDelay: Double
    var restoreAfter: Double
    var reopen: Bool
    var reopenAfter: Double
    var secondWindow: Bool
    var autoOpen: Bool
    var tag: String

    static func fromProcess() -> M3CConfig {
        let d = UserDefaults.standard
        func str(_ key: String, _ def: String) -> String { d.string(forKey: key) ?? def }
        func dbl(_ key: String, _ def: Double) -> Double {
            d.object(forKey: key) == nil ? def : d.double(forKey: key)
        }
        func bool(_ key: String, _ def: Bool) -> Bool {
            d.object(forKey: key) == nil ? def : d.bool(forKey: key)
        }
        return M3CConfig(
            park: str("M3CPark", "hidden"),
            parkWhen: str("M3CParkWhen", "open"),
            parkScope: str("M3CParkScope", "all"),
            openDelay: dbl("M3COpenDelay", 1.0),
            restoreAfter: dbl("M3CRestoreAfter", -1),
            reopen: bool("M3CReopen", false),
            reopenAfter: dbl("M3CReopenAfter", 5.0),
            secondWindow: bool("M3CSecondWindow", false),
            autoOpen: bool("M3CAutoOpen", true),
            tag: str("M3CTag", "unset"))
    }

    var summary: String {
        "tag=\(tag) park=\(park) parkWhen=\(parkWhen) parkScope=\(parkScope) openDelay=\(openDelay) " +
        "restoreAfter=\(restoreAfter) reopen=\(reopen) reopenAfter=\(reopenAfter) " +
        "secondWindow=\(secondWindow) autoOpen=\(autoOpen)"
    }
}
