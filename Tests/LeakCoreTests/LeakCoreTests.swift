//
//  LeakCoreTests.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Testing
@testable import LeakCore

@MainActor
@Suite(.serialized)
struct LeakCoreTests {
    init() { LeakCore.resetForTesting() }

    @Test func installIsIdempotent() {
        #expect(LeakCore.markInstalled() == true)
        #expect(LeakCore.markInstalled() == false)
        #expect(LeakCore.isInstalled)
    }
}
#endif
