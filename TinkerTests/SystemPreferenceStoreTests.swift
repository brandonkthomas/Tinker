//
//  SystemPreferenceStoreTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// Exercises the real preferences system in a domain nothing else reads.
struct SystemPreferenceStoreTests {
    @Test func valuesRoundTripAndCanBeRemoved() throws {
        let store = SystemPreferenceStore()
        let location = PreferenceLocation(domain: "net.brandonthomas.Tinker.tests", key: "RoundTrip")
        defer { try? store.setValue(nil, at: location) }

        for value: PreferenceValue in [.bool(true), .int(7), .double(0.25), .string("scale")] {
            try store.setValue(value, at: location)
            #expect(store.value(at: location) == value)
        }

        try store.setValue(nil, at: location)
        #expect(store.value(at: location) == nil)
    }

    /// Only apps the catalog marks as sandboxed are read from their container.
    /// Reaching into any other app's container makes macOS ask for access to
    /// that app's data.
    @Test func onlyMarkedLocationsUseAnAppContainer() {
        // TextEdit usually has a container folder; without the mark it must not be used.
        let unmarked = PreferenceLocation(domain: "com.apple.TextEdit", key: "RichText")
        #expect(SystemPreferenceStore.applicationIdentifier(for: unmarked) == "com.apple.TextEdit")

        var missing = PreferenceLocation(domain: "com.example.no-such-app", key: "Key")
        missing.isInAppContainer = true
        #expect(SystemPreferenceStore.applicationIdentifier(for: missing) == "com.example.no-such-app")
    }

    @Test func systemScopeRefusesToWrite() {
        let location = PreferenceLocation(domain: "net.brandonthomas.Tinker.tests", key: "K", scope: .system)
        #expect(throws: PreferenceError.self) {
            try SystemPreferenceStore().setValue(.bool(true), at: location)
        }
    }
}
