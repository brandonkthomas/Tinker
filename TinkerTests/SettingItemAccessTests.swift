//
//  SettingItemAccessTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// What a setting does when Tinker lacks the permission it needs.
@MainActor
struct SettingItemAccessTests {
    let store = InMemoryPreferenceStore()
    let systemSettings = FakeSystemSettings()
    let restartQueue = RestartQueue()
    let access = AccessStatus()

    private func item(_ definition: SettingDefinition) -> SettingItem {
        SettingItem(
            definition: definition, store: store, systemSettings: systemSettings,
            restartQueue: restartQueue, access: access
        )
    }

    @Test func systemScopeUnlocksWithAdministratorAccess() throws {
        let item = item(try preferenceSetting(
            control: #"{ "type": "toggle", "on": true, "off": false, "unset": "off" }"#,
            extra: #", "scope": "system""#
        ))
        #expect(item.blocker == .administratorAccess)
        store.allowsSystemWrites = true
        access.hasAdministratorAccess = true
        #expect(item.isEditable)

        item.isOn = true
        #expect(item.isOn)
        #expect(item.errorMessage == nil)
    }

    /// Without Full Disk Access a sandboxed app's value is unknown, not "off".
    @Test func containerSettingsAreUnknownWithoutFullDiskAccess() throws {
        var location = testLocation
        location.isInAppContainer = true
        store.values[location] = .bool(true)
        let item = item(try settingDefinition("""
        {
          "id": "test.container", "category": "test", "group": "Group", "title": "Title", "tier": "recommended",
          "store": { "domain": "com.example.test", "key": "Key" }, "valueType": "bool",
          "control": { "type": "toggle", "on": true, "off": false, "unset": "off" },
          "needsFullDiskAccess": true
        }
        """))
        #expect(item.blocker == .fullDiskAccess)
        #expect(!item.isReadable)
        #expect(!item.matches(.bool(true)))
        #expect(!item.matches(.bool(false)))

        item.isOn = false
        #expect(store.values[location] == .bool(true))

        access.hasFullDiskAccess = true
        item.reload()
        #expect(item.isReadable)
        #expect(item.isOn)
    }

    @Test func systemScopeIsReadOnlyAndReportsWhy() throws {
        let item = item(try preferenceSetting(
            control: #"{ "type": "toggle", "on": true, "off": false, "unset": "off" }"#,
            extra: #", "scope": "system""#
        ))
        #expect(!item.isEditable)

        item.isOn = true
        #expect(!item.isOn)
        #expect(item.errorMessage != nil)
    }
}
