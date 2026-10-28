import Foundation

enum AppleScriptError: Error, LocalizedError {
    case compileFailed(String)
    case executionFailed(code: Int, message: String)

    /// -1743: user denied Automation; -10004: privilege violation (also permission-related).
    var isPermissionDenied: Bool {
        if case .executionFailed(let code, _) = self { return code == -1743 || code == -10004 }
        return false
    }

    /// -600: the target application is not running.
    var isTargetNotRunning: Bool {
        if case .executionFailed(let code, _) = self { return code == -600 }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .compileFailed(let m): return "AppleScript compile error: \(m)"
        case .executionFailed(let code, let m): return "AppleScript error \(code): \(m)"
        }
    }
}

/// Runs AppleScript off the main thread on a serial queue. Each call compiles its own
/// `NSAppleScript` (a few ms) because instances are not thread-safe to share.
/// The first call targeting an app triggers the macOS Automation consent dialog.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "com.macisland.applescript", qos: .userInitiated)

    func run<T: Sendable>(_ source: String, _ transform: @escaping @Sendable (NSAppleEventDescriptor) -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: AppleScriptError.compileFailed("could not create script"))
                    return
                }
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
                    continuation.resume(throwing: AppleScriptError.executionFailed(code: code, message: message))
                    return
                }
                continuation.resume(returning: transform(result))
            }
        }
    }

    func run(_ source: String) async throws {
        try await run(source) { _ in () }
    }
}
