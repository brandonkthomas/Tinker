//
//  HelperPolicyTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// Which preference keys the root helper agrees to write.
struct HelperPolicyTests {
    /// The helper's compiled-in list must cover exactly the catalog's administrator-only keys.
    @Test func allowedKeysMatchTheCatalog() throws {
        var expected: [String: Set<String>] = [:]
        for setting in try Catalog.bundled().settings {
            guard let store = setting.store, store.scope == .system else { continue }
            expected[store.domain, default: []].formUnion(store.locations.map(\.key))
        }
        #expect(HelperPolicy.allowedKeys == expected)
    }

    @Test func onlyListedKeysAreAccepted() {
        #expect(HelperPolicy.rejection(domain: "com.apple.loginwindow", key: "GuestEnabled", value: .bool(false)) == nil)
        #expect(HelperPolicy.rejection(domain: "com.apple.loginwindow", key: "GuestEnabled", value: nil) == nil)
        #expect(HelperPolicy.rejection(domain: "com.apple.loginwindow", key: "LoginHook", value: .string("/tmp/x")) != nil)
        #expect(HelperPolicy.rejection(domain: "com.apple.dock", key: "autohide", value: .bool(true)) != nil)
    }

    @Test func overlongStringsAreRefused() {
        let long = String(repeating: "x", count: HelperPolicy.maximumStringLength + 1)
        #expect(HelperPolicy.rejection(domain: "com.apple.loginwindow", key: "LoginwindowText", value: .string(long)) != nil)
    }
}
