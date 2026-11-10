//
//  LeakSuppression.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// A known leak: only logged until `expires`, reported as new afterwards.
package struct LeakSuppression: Sendable, Equatable {
    package let signature: LeakSignature
    package let reason: String
    package let owner: String
    /// As written in the file, `yyyy-MM-dd`, inclusive.
    package let expires: String
    /// Midnight after `expires`.
    package let endsAt: Date
}

/// Reads the suppression file. Never fails: a broken entry is skipped and described in `problems`.
package enum LeakSuppressionFile {
    package struct Loaded {
        package var suppressions: [LeakSuppression] = []
        package var problems: [String] = []

        package init(suppressions: [LeakSuppression] = [], problems: [String] = []) {
            self.suppressions = suppressions
            self.problems = problems
        }
    }

    package static func load(_ url: URL, timeZone: TimeZone = .current) -> Loaded {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return Loaded(problems: ["\(url.lastPathComponent): cannot be read, file ignored"])
        }
        return parse(data, source: url.lastPathComponent, timeZone: timeZone)
    }

    package static func parse(_ data: Data, source: String, timeZone: TimeZone = .current) -> Loaded {
        var loaded = Loaded()
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
            loaded.problems.append("\(source): not valid JSON (\(detail)), file ignored")
            return loaded
        }
        guard let file = root as? [String: Any], let entries = file["suppressions"] as? [Any] else {
            loaded.problems.append(#"\#(source): expected {"version": 1, "suppressions": [...]}, file ignored"#)
            return loaded
        }
        if let version = file["version"], (version as? Int) != 1 {
            loaded.problems.append("\(source): unsupported version \(version), expected 1, file ignored")
            return loaded
        }

        let dates = DateParser(timeZone: timeZone)
        for (index, raw) in entries.enumerated() {
            do {
                loaded.suppressions.append(try suppression(from: raw, dates: dates))
            } catch {
                let entry = (((raw as? [String: Any])?["signature"] as? [String: Any])?["type"] as? String)
                    .map { "suppressions[\(index)] (\($0))" } ?? "suppressions[\(index)]"
                loaded.problems.append("\(source): \(entry): \(error.message), entry ignored")
            }
        }
        return loaded
    }

    private struct Invalid: Error {
        let message: String
    }

    private static func suppression(from raw: Any, dates: DateParser) throws(Invalid) -> LeakSuppression {
        guard let entry = raw as? [String: Any] else { throw Invalid(message: "must be an object") }
        guard let signature = entry["signature"] as? [String: Any] else {
            throw Invalid(message: #"missing "signature": {"type": ..., "kind": ...}"#)
        }
        let type = try text("type", in: signature)
        let kindName = try text("kind", in: signature)
        guard let kind = LeakKind(rawValue: kindName) else {
            let kinds = LeakKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw Invalid(message: #""kind" is "\#(kindName)", expected one of \#(kinds)"#)
        }
        let expires = try text("expires", in: entry)
        guard let endsAt = dates.dayAfter(expires) else {
            throw Invalid(message: #""expires" is "\#(expires)", expected a date like 2026-12-31"#)
        }
        return LeakSuppression(
            signature: LeakSignature(typeName: type, kind: kind),
            reason: try text("reason", in: entry),
            owner: try text("owner", in: entry),
            expires: expires,
            endsAt: endsAt)
    }

    private static func text(_ key: String, in object: [String: Any]) throws(Invalid) -> String {
        guard let value = object[key] else { throw Invalid(message: #"missing "\#(key)""#) }
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Invalid(message: #""\#(key)" must be a non-empty string"#)
        }
        return string
    }

    private struct DateParser {
        private let calendar: Calendar
        private let formatter = DateFormatter()

        init(timeZone: TimeZone) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            self.calendar = calendar
            formatter.calendar = calendar
            formatter.timeZone = timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
        }

        func dayAfter(_ text: String) -> Date? {
            formatter.date(from: text).flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        }
    }
}

#endif
