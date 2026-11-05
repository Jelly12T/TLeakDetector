//
//  PropertyScannerTests.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Testing
@testable import LeakCore

private final class ViewModel {}
private final class Service {}
private struct Value { let x = 1 }

private class BaseScreen {
    let baseModel = ViewModel()
}

private final class Screen: BaseScreen {
    let model = ViewModel()
    var optionalModel: ViewModel? = ViewModel()
    var missing: ViewModel?
    let value = Value()
    let number = 42
    let service = Service()
    lazy var lazyModel = ViewModel()
}

@Suite("PropertyScanner")
struct PropertyScannerTests {
    @Test("Finds class instances in direct, optional, lazy and superclass properties")
    func findsClassProperties() {
        let screen = Screen()
        _ = screen.lazyModel
        let found = PropertyScanner.classProperties(of: screen) { ObjectIdentifier($0) == ObjectIdentifier(ViewModel.self) }
        #expect(found.map(\.label) == ["model", "optionalModel", "lazyModel", "baseModel"])
        let sameInstance = found.first.map { $0.object === screen.model } ?? false
        #expect(sameInstance)
    }

    @Test("Filter excludes types; value types and nil optionals are skipped")
    func filtersAndSkips() {
        let screen = Screen()
        let all = PropertyScanner.classProperties(of: screen) { _ in true }
        #expect(all.map(\.label) == ["model", "optionalModel", "service", "baseModel"])  // lazy not yet loaded
    }
}

#endif
