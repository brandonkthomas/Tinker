//
//  PreferenceValueTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

struct PreferenceValueTests {
    @Test func coercionMakesEquivalentValuesEqual() {
        #expect(PreferenceValue.int(1).coerced(to: .bool) == .bool(true))
        #expect(PreferenceValue.string("YES").coerced(to: .bool) == .bool(true))
        #expect(PreferenceValue.int(0).coerced(to: .double) == .double(0))
        #expect(PreferenceValue.string("10").coerced(to: .int) == .int(10))
        #expect(PreferenceValue.double(9.6).coerced(to: .intString) == .string("10"))
        #expect(PreferenceValue.string("genie").coerced(to: .int) == nil)
    }

    @Test func propertyListRoundTripKeepsTheType() {
        for value: PreferenceValue in [.bool(true), .bool(false), .int(1), .int(0), .double(0.5), .string("x")] {
            #expect(PreferenceValue(propertyList: value.propertyList) == value)
        }
    }

    @Test func valuesSurviveTheTripToTheHelper() {
        for value: PreferenceValue? in [nil, .bool(true), .bool(false), .int(-3), .double(0.25), .string("Hello, \"Mac\"")] {
            let wire = PreferenceValue.wireForm(of: value)
            #expect(PreferenceValue.fromWireForm(kind: wire.kind, payload: wire.payload) == .some(value))
        }
        #expect(PreferenceValue.fromWireForm(kind: "bool", payload: "maybe") == nil)
        #expect(PreferenceValue.fromWireForm(kind: "plist", payload: "") == nil)
    }
}
