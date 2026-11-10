import Foundation

enum LabLog {
    static func log(_ message: String) {
        LLLogMessage(message)
    }
}
