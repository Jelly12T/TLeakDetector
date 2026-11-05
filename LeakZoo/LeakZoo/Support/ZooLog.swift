//
//  ZooLog.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import Foundation

enum ZooLog {
    /// Prints `[LeakZoo] t=<uptime> <message>`. Safe to call from deinit.
    static func log(_ message: String) {
        print(String(format: "[LeakZoo] t=%.3f %@", ProcessInfo.processInfo.systemUptime, message))
        fflush(stdout)
    }
}
