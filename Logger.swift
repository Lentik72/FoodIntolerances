import Foundation
import os.log

/// Centralized logging utility with log levels and production-safe behavior
enum Logger {

    /// Log levels in order of severity
    enum Level: String {
        case debug = "🔍 DEBUG"
        case info = "ℹ️ INFO"
        case warning = "⚠️ WARNING"
        case error = "❌ ERROR"

        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
    }

    /// Log categories for filtering
    enum Category: String {
        case app = "App"
        case data = "Data"
        case ui = "UI"
        case network = "Network"
        case location = "Location"
        case health = "Health"
        case notification = "Notification"
        case migration = "Migration"
    }

    // MARK: - Configuration

    /// Enable/disable logging (automatically disabled in release builds)
    #if DEBUG
    private static var isEnabled = true
    #else
    private static var isEnabled = false
    #endif

    /// Minimum log level to display
    private static var minimumLevel: Level = .debug

    /// Use os.log for system integration
    private static let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "FoodIntolerances", category: "App")

    // MARK: - Public Logging Methods

    /// Log a debug message (development only)
    static func debug(
        _ message: String,
        category: Category = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    /// Log an info message
    static func info(
        _ message: String,
        category: Category = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    /// Log a warning message
    static func warning(
        _ message: String,
        category: Category = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    /// Log an error message
    static func error(
        _ message: String,
        category: Category = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    /// Log an error with the Error object
    static func error(
        _ error: Error,
        message: String? = nil,
        category: Category = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let errorMessage = message.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription
        log(errorMessage, level: .error, category: category, file: file, function: function, line: line)
    }

    // MARK: - Private Implementation

    private static func log(
        _ message: String,
        level: Level,
        category: Category,
        file: String,
        function: String,
        line: Int
    ) {
        guard isEnabled else { return }
        guard level.rawValue >= minimumLevel.rawValue else { return }

        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(category.rawValue)] \(level.rawValue): \(message)"

        #if DEBUG
        // Pretty print for debug console
        print("\(logMessage) (\(fileName):\(line))")
        #endif

        // Also log to unified logging system for Console.app
        os_log("%{public}@", log: osLog, type: level.osLogType, logMessage)
    }

    // MARK: - Configuration Methods

    /// Enable or disable logging at runtime
    static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// Set the minimum log level
    static func setMinimumLevel(_ level: Level) {
        minimumLevel = level
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log data operation
    static func data(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        debug(message, category: .data, file: file, function: function, line: line)
    }

    /// Log network operation
    static func network(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        debug(message, category: .network, file: file, function: function, line: line)
    }

    /// Log UI event
    static func ui(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        debug(message, category: .ui, file: file, function: function, line: line)
    }
}
