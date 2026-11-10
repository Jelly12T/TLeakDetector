//
//  LeakReporter.swift
//  TLeakDetector
//
//  Created by thachlh on 9/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import os

public enum LeakReportMode: String, Sendable {
    case crash
    case debugger
    case log
}

package enum LeakLog {
    package static let subsystem = "TLeakDetector"
    package static let leaks = Logger(subsystem: subsystem, category: "leak")
    package static let marks = Logger(subsystem: subsystem, category: "mark")
    package static let config = Logger(subsystem: subsystem, category: "config")
    package static let warnings = Logger(subsystem: subsystem, category: "warning")
    /// Retain graph searches as intervals, for Instruments' os_signpost view.
    package static let graph = OSSignposter(subsystem: subsystem, category: "graph")

    /// The unified log truncates long messages: a report goes out in pieces, split between lines.
    package static func pieces(of message: String, limit: Int = 900) -> [String] {
        var pieces: [String] = []
        var current = ""
        for line in message.split(separator: "\n", omittingEmptySubsequences: false) {
            if !current.isEmpty, current.utf8.count + line.utf8.count + 1 > limit {
                pieces.append(current)
                current = "[TLeakDetector] (continued)"
            }
            current += current.isEmpty ? String(line) : "\n" + line
        }
        pieces.append(current)
        return pieces
    }
}

/// Shows each leak signature once per run: logs it, then stops in the debugger or crashes,
/// unless a suppression still covers it.
@MainActor
package final class LeakReporter {
    package struct Effects {
        package var log: @MainActor (OSLogType, String) -> Void
        package var now: @MainActor () -> Date
        package var isDebuggerAttached: @MainActor () -> Bool
        package var breakIntoDebugger: @MainActor () -> Void
        package var crash: @MainActor (String) -> Void
        package var write: @MainActor (Data, URL) -> Bool
        package var warn: @MainActor (String) -> Void

        package init(
            log: @escaping @MainActor (OSLogType, String) -> Void,
            now: @escaping @MainActor () -> Date,
            isDebuggerAttached: @escaping @MainActor () -> Bool,
            breakIntoDebugger: @escaping @MainActor () -> Void,
            crash: @escaping @MainActor (String) -> Void,
            write: @escaping @MainActor (Data, URL) -> Bool = { _, _ in false },
            warn: @escaping @MainActor (String) -> Void = { _ in }
        ) {
            self.warn = warn
            self.log = log
            self.now = now
            self.isDebuggerAttached = isDebuggerAttached
            self.breakIntoDebugger = breakIntoDebugger
            self.crash = crash
            self.write = write
        }

        package static var live: Effects {
            Effects(
                log: { level, message in
                    for piece in LeakLog.pieces(of: message) {
                        LeakLog.leaks.log(level: level, "\(piece, privacy: .public)")
                    }
                },
                now: { Date() },
                isDebuggerAttached: LeakReporter.isDebuggerAttached,
                breakIntoDebugger: { _ = raise(SIGTRAP) },
                crash: { assertionFailure($0) },
                write: { data, url in
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    return (try? data.write(to: url)) != nil
                },
                warn: { message in
                    for piece in LeakLog.pieces(of: message) {
                        LeakLog.warnings.log(level: .default, "\(piece, privacy: .public)")
                    }
                })
        }
    }

    /// `nil`: stop in the debugger if one is attached, crash otherwise.
    private let mode: LeakReportMode?
    private let suppressions: [LeakSuppression]
    private let exportDirectory: URL?
    private let effects: Effects
    private var reported: Set<LeakSignature> = []
    private var warned: Set<String> = []
    private let ignoredPatterns: Set<LeakPattern>

    package init(
        mode: LeakReportMode? = nil,
        suppressions: [LeakSuppression] = [],
        exportDirectory: URL? = nil,
        ignoredPatterns: Set<LeakPattern> = [],
        effects: Effects = .live
    ) {
        self.ignoredPatterns = ignoredPatterns
        self.mode = mode
        self.suppressions = suppressions
        self.exportDirectory = exportDirectory
        self.effects = effects
    }

    package func report(_ finding: some LeakFinding) {
        guard reported.insert(finding.signature).inserted else { return }
        var message = finding.description
        if let suppression = suppressions.first(where: { $0.covers(finding.signature) }) {
            let note = "\(suppression.reason) (owner: \(suppression.owner))"
            guard effects.now() >= suppression.endsAt else {
                effects.log(.default, message + "\n  suppressed until \(suppression.expires): \(note)")
                return
            }
            message += "\n  suppression expired on \(suppression.expires): \(note)"
        }
        if let leak = finding as? LeakReport, let files = export(leak) {
            message += "\n  graph: \(files.dot.path)\n         \(files.json.path)"
        }
        // Resolved per report: a debugger can be attached after launch.
        switch mode ?? (effects.isDebuggerAttached() ? .debugger : .crash) {
        case .log:
            effects.log(.error, message)
        case .debugger:
            effects.log(.error, message + "\n  Paused by TLeakDetector. Continue to resume.")
            effects.breakIntoDebugger()
        case .crash:
            effects.log(.error, message)
            effects.crash(message)
        }
    }

    /// Logged once per pattern and place. Never pauses or crashes: nothing has leaked yet.
    package func warn(_ warning: LeakWarning) {
        guard !ignoredPatterns.contains(warning.pattern), warned.insert(warning.key).inserted else { return }
        effects.warn(warning.description)
    }

    /// The searched graph as `<time>-<Type>.dot` and `.json`, the cause highlighted.
    private func export(_ report: LeakReport) -> (dot: URL, json: URL)? {
        guard let directory = exportDirectory, let analysis = report.analysis, let graph = analysis.explored else { return nil }
        let name = "\(Self.fileTime.string(from: effects.now()))-\(report.leaked.typeName)"
        let dot = directory.appendingPathComponent(name + ".dot"), json = directory.appendingPathComponent(name + ".json")
        guard effects.write(Data(graph.dot(highlighting: analysis.highlighted).utf8), dot),
              effects.write(graph.json(highlighting: analysis.highlighted), json) else { return nil }
        return (dot, json)
    }

    private static let fileTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    nonisolated package static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }
}

#endif
