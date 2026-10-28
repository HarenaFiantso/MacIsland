import os

/// Unified logging. Read with:
///   log stream --predicate 'subsystem == "com.macisland.MacIsland"' --level debug
enum Log {
    static let subsystem = "com.macisland.MacIsland"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let island = Logger(subsystem: subsystem, category: "island")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let shelf = Logger(subsystem: subsystem, category: "shelf")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let system = Logger(subsystem: subsystem, category: "system")
}
