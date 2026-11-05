//
//  FieldOwnershipSpikeTests.swift
//  FieldOwnershipSpike
//
//  Created by thachlh on 5/11/26.
//
//  SPIKE CODE — `testReport` never fails (also run with reflection metadata reduced or
//  disabled). `testExpectations` asserts everything matched; meaningful with full metadata.
//

import XCTest
import SpikeReport

final class FieldOwnershipSpikeTests: XCTestCase {
    func testReport() {
        SpikeReport.run()
    }

    func testExpectations() {
        let failures = SpikeReport.run()
        XCTAssertTrue(failures.isEmpty, "Failed checks: \(failures)")
    }
}
