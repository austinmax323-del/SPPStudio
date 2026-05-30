import Foundation
import os.log

public enum LogCategory: String, CaseIterable, Sendable {
    case ide            = "ide"
    case build          = "build"
    case runtime        = "runtime"
    case hook           = "hook"
    case export         = "export"
    case simulator      = "simulator"
    case plugin         = "plugin"
    case ui             = "ui"
    case index          = "index"
    case device         = "device"
    case instrumentation = "instrumentation"
    case serialization  = "serialization"
}

public struct SPPLogger: Sendable {
    private let logger: Logger
    public let category: LogCategory

    public init(category: LogCategory, subsystem: String = "com.spp.studio") {
        self.category = category
        self.logger = Logger(subsystem: subsystem, category: category.rawValue)
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    public func critical(_ message: String) {
        logger.critical("\(message, privacy: .public)")
    }

    public func error(_ sppError: SPPError) {
        logger.error("\(sppError.localizedDescription, privacy: .public)")
    }
}

public extension SPPLogger {
    static let ide            = SPPLogger(category: .ide)
    static let build          = SPPLogger(category: .build)
    static let runtime        = SPPLogger(category: .runtime)
    static let hook           = SPPLogger(category: .hook)
    static let export         = SPPLogger(category: .export)
    static let simulator      = SPPLogger(category: .simulator)
    static let plugin         = SPPLogger(category: .plugin)
    static let ui             = SPPLogger(category: .ui)
    static let index          = SPPLogger(category: .index)
    static let device         = SPPLogger(category: .device)
    static let instrumentation = SPPLogger(category: .instrumentation)
    static let serialization  = SPPLogger(category: .serialization)
}
