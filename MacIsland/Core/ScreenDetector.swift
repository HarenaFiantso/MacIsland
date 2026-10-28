import AppKit
import IslandCore

/// Translates `NSScreen` into the UI-free `NotchGeometry`.
@MainActor
enum ScreenDetector {
    static let fallbackNotchWidth: CGFloat = 185

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func geometry(for screen: NSScreen, preferences: Preferences) -> NotchGeometry {
        let id = displayID(of: screen)
        let insets = screen.safeAreaInsets
        let hasNotch = insets.top > 0
        // visibleFrame excludes the menu bar; when the bar auto-hides this is 0, so keep a floor.
        let measuredMenuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let menuBarHeight = measuredMenuBar > 0 ? measuredMenuBar : (hasNotch ? insets.top : NSStatusBar.system.thickness + 2)

        let notchSize: CGSize
        if hasNotch {
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX > left.maxX {
                notchSize = CGSize(width: right.minX - left.maxX, height: insets.top)
            } else {
                notchSize = CGSize(width: fallbackNotchWidth, height: insets.top)
            }
        } else {
            notchSize = CGSize(
                width: preferences.virtualNotchWidth,
                height: max(preferences.virtualNotchHeight, menuBarHeight)
            )
        }

        return NotchGeometry(
            displayID: id,
            screenFrame: screen.frame,
            hasPhysicalNotch: hasNotch,
            isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            notchSize: notchSize,
            menuBarHeight: menuBarHeight,
            maximumFramesPerSecond: screen.maximumFramesPerSecond
        )
    }

    /// Screens that should host an island according to the preferences.
    static func eligibleScreens(preferences: Preferences) -> [NSScreen] {
        let all = NSScreen.screens
        var candidates: [NSScreen]
        switch preferences.screenMode {
        case .builtIn:
            candidates = all.filter { CGDisplayIsBuiltin(displayID(of: $0)) != 0 }
            if candidates.isEmpty, let first = all.first { candidates = [first] } // clamshell mode
        case .primary:
            candidates = all.first.map { [$0] } ?? []
        case .all:
            candidates = all
        }
        if !preferences.showOnScreensWithoutNotch {
            candidates = candidates.filter { $0.safeAreaInsets.top > 0 }
        }
        return candidates
    }
}
