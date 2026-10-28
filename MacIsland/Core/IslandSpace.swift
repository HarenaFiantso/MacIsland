import AppKit

/// A private window-server Space that hosts every island panel.
///
/// Why: a panel that merely `canJoinAllSpaces` is still a member of each *user* Space.
/// During a desktop switch the WindowServer therefore renders it twice — sliding out
/// with the old desktop and in with the new one — so the island visibly moves while
/// the physical notch obviously does not. The Dock and Notification Center avoid this
/// by living in Spaces of their own, and so does Alcove (observed in 1.7.7:
/// `CGSSpaceCreate` → `CGSSpaceSetAbsoluteLevel(…, 400)` → `CGSShowSpaces` →
/// `CGSAddWindowsToSpaces` / `CGSRemoveWindowsFromSpaces`). A Space at absolute
/// level 400 is composited above every user Space and every full-screen app, takes no
/// part in the switch animation and is ignored by Mission Control.
///
/// These `CGS*` functions are private (CoreGraphics re-exports them from SkyLight).
/// They are resolved with `dlsym` at run time, never linked: should a future macOS
/// drop one, `isAvailable` turns false and the panels fall back to the public
/// `canJoinAllSpaces` behaviour.
@MainActor
final class IslandSpace {
    static let shared = IslandSpace()

    /// Absolute level Alcove uses; user desktops sit at 0.
    static let absoluteLevel: Int32 = 400
    /// `CGSSpaceMask` values: 0x7 = current + other + user Spaces (what a desktop
    /// switch animates); 0xF also includes unmanaged Spaces such as ours.
    private static let userSpacesMask: Int32 = 0x7
    private static let allSpacesMask: Int32 = 0xF

    private typealias ConnectionID = Int32
    private typealias SpaceID = UInt64

    private typealias MainConnectionFn = @convention(c) () -> ConnectionID
    private typealias SpaceCreateFn = @convention(c) (ConnectionID, Int32, CFDictionary?) -> SpaceID
    private typealias SpaceDestroyFn = @convention(c) (ConnectionID, SpaceID) -> Void
    private typealias SpaceLevelFn = @convention(c) (ConnectionID, SpaceID, Int32) -> Void
    private typealias WindowsSpacesFn = @convention(c) (ConnectionID, CFArray, CFArray) -> Void
    private typealias SpacesFn = @convention(c) (ConnectionID, CFArray) -> Void
    private typealias ActiveSpaceFn = @convention(c) (ConnectionID) -> SpaceID
    private typealias CopySpacesForWindowsFn = @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?

    private struct API {
        let mainConnection: MainConnectionFn
        let create: SpaceCreateFn
        let destroy: SpaceDestroyFn
        let setAbsoluteLevel: SpaceLevelFn
        let addWindows: WindowsSpacesFn
        let removeWindows: WindowsSpacesFn
        let show: SpacesFn
        let hide: SpacesFn
        let activeSpace: ActiveSpaceFn
        let copySpacesForWindows: CopySpacesForWindowsFn?

        init?() {
            guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
            func load<T>(_ name: String, _: T.Type) -> T? {
                guard let symbol = dlsym(handle, name) else { return nil }
                return unsafeBitCast(symbol, to: T.self)
            }
            guard let mainConnection = load("CGSMainConnectionID", MainConnectionFn.self),
                  let create = load("CGSSpaceCreate", SpaceCreateFn.self),
                  let destroy = load("CGSSpaceDestroy", SpaceDestroyFn.self),
                  let setAbsoluteLevel = load("CGSSpaceSetAbsoluteLevel", SpaceLevelFn.self),
                  let addWindows = load("CGSAddWindowsToSpaces", WindowsSpacesFn.self),
                  let removeWindows = load("CGSRemoveWindowsFromSpaces", WindowsSpacesFn.self),
                  let show = load("CGSShowSpaces", SpacesFn.self),
                  let hide = load("CGSHideSpaces", SpacesFn.self),
                  let activeSpace = load("CGSGetActiveSpace", ActiveSpaceFn.self)
            else { return nil }
            self.mainConnection = mainConnection
            self.create = create
            self.destroy = destroy
            self.setAbsoluteLevel = setAbsoluteLevel
            self.addWindows = addWindows
            self.removeWindows = removeWindows
            self.show = show
            self.hide = hide
            self.activeSpace = activeSpace
            self.copySpacesForWindows = load("CGSCopySpacesForWindows", CopySpacesForWindowsFn.self)
        }
    }

    private let api: API?
    private let connection: ConnectionID
    private var spaceID: SpaceID = 0
    private var attached: Set<Int> = []

    private init() {
        api = API()
        connection = api?.mainConnection() ?? 0
        if api == nil {
            Log.window.error("private space unavailable: CGS functions not found, falling back to canJoinAllSpaces")
        }
    }

    /// False when the private functions could not be resolved on this macOS.
    var isAvailable: Bool { api != nil }

    /// Identifier of the private Space, 0 until the first window is attached.
    var currentSpaceID: UInt64 { spaceID }

    /// Moves `window` into the private Space and out of every user Space it belongs to.
    /// Idempotent: call it again whenever the window is ordered back on screen, since
    /// AppKit re-inserts an ordered-in window into the active user Space.
    func attach(_ window: NSWindow) {
        guard let api, let space = ensureSpace() else { return }
        let number = window.windowNumber
        guard number > 0 else { return }
        let windows = [number] as CFArray
        api.addWindows(connection, windows, [space] as CFArray)
        // Membership in the user Spaces must go, otherwise the WindowServer keeps
        // drawing the window there as well — that is the duplicate seen while switching.
        let others = userSpaces(containing: number).filter { $0 != space }
        if !others.isEmpty {
            api.removeWindows(connection, windows, others as CFArray)
        }
        attached.insert(number)
        Log.window.debug("window \(number) attached to private space \(space), left spaces \(others)")
    }

    func detach(_ window: NSWindow) {
        guard let api, spaceID != 0 else { return }
        let number = window.windowNumber
        guard number > 0, attached.remove(number) != nil else { return }
        api.removeWindows(connection, [number] as CFArray, [spaceID] as CFArray)
    }

    /// Every Space currently containing `windowNumber`, our own included
    /// (diagnostics; nil when the query function is unavailable).
    func spaces(containing windowNumber: Int) -> [UInt64]? {
        spaces(containing: windowNumber, mask: Self.allSpacesMask)
    }

    private func spaces(containing windowNumber: Int, mask: Int32) -> [UInt64]? {
        guard let api, let copy = api.copySpacesForWindows else { return nil }
        guard let array = copy(connection, mask, [windowNumber] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return array.map(\.uint64Value)
    }

    private func ensureSpace() -> SpaceID? {
        guard let api else { return nil }
        if spaceID != 0 { return spaceID }
        let id = api.create(connection, 1, nil)
        guard id != 0 else {
            Log.window.error("private space: CGSSpaceCreate failed")
            return nil
        }
        api.setAbsoluteLevel(connection, id, Self.absoluteLevel)
        api.show(connection, [id] as CFArray)
        spaceID = id
        Log.window.notice("private space \(id) created at absolute level \(Self.absoluteLevel)")
        return id
    }

    /// User Spaces the window belongs to — an empty list once it only lives in ours.
    /// Without the query function, assume the active Space (where AppKit puts a
    /// window it orders in).
    private func userSpaces(containing number: Int) -> [SpaceID] {
        if let known = spaces(containing: number, mask: Self.userSpacesMask) { return known }
        guard let api else { return [] }
        return [api.activeSpace(connection)]
    }
}
