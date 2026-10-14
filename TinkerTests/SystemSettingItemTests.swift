//
//  SystemSettingItemTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// Settings backed by a system tool instead of a preference key.
@MainActor
struct SystemSettingItemTests {
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

    private func systemItem(_ setting: String, valueType: String = "bool", control: String, profileValue: String? = nil) throws -> SettingItem {
        item(try settingDefinition("""
        {
          "id": "test.system", "category": "test", "group": "Group", "title": "Title", "tier": "recommended",
          "system": "\(setting)", "valueType": "\(valueType)", "control": \(control)
          \(profileValue.map { ", \"profileValue\": \($0)" } ?? "")
        }
        """))
    }

    @Test func statusSettingReportsStateAndOffersMatchingActions() throws {
        systemSettings.values[.homebrew] = .bool(false)
        let item = try systemItem("homebrew", control: """
        { "type": "status", "onLabel": "Installed", "offLabel": "Not installed",
          "actions": [{ "title": "Install", "value": true, "when": "off" }] }
        """, profileValue: "true")
        #expect(item.statusIsOn == false)
        #expect(item.currentDisplayText == "Not installed")
        #expect(!item.matches(.bool(true)))
        #expect(item.blocker == nil)
        // Installing opens Terminal, so a profile never does it.
        #expect(!item.canApplyInBulk)
        #expect(!item.canReset)

        item.apply(.bool(true))
        #expect(item.currentDisplayText == "Installed")
    }

    @Test func rootSystemSettingsNeedAdministratorAccess() throws {
        systemSettings.values[.firewall] = .bool(false)
        let item = try systemItem("firewall", control: #"{ "type": "toggle", "on": true, "off": false, "unset": "off" }"#)
        #expect(item.blocker == .administratorAccess)
        item.isOn = true
        #expect(systemSettings.values[.firewall] == .bool(false))

        access.hasAdministratorAccess = true
        #expect(item.canApplyInBulk)
        item.isOn = true
        #expect(systemSettings.values[.firewall] == .bool(true))
        #expect(item.isOn)
    }

    /// Gatekeeper itself is only ever switched on; "off" is not something Tinker does.
    @Test func gatekeeperAnywhereOptionIsItsOwnSwitch() throws {
        systemSettings.values[.gatekeeperAnywhereOption] = .bool(false)
        access.hasAdministratorAccess = true
        let item = try systemItem("gatekeeperAnywhereOption", control: #"{ "type": "toggle", "on": true, "off": false, "unset": "off" }"#)
        #expect(!item.isOn)

        item.isOn = true
        #expect(systemSettings.values[.gatekeeperAnywhereOption] == .bool(true))
        #expect(item.errorMessage == nil)
    }

    @Test func readOnlySystemSettingIsNeverApplied() throws {
        systemSettings.values[.systemIntegrityProtection] = .bool(true)
        let item = try systemItem("systemIntegrityProtection", control: #"{ "type": "status", "onLabel": "Enabled", "offLabel": "Disabled" }"#)
        #expect(item.currentDisplayText == "Enabled")
        #expect(!item.canApplyInBulk)
    }

    @Test func aFailedSystemChangeIsReportedOnTheRow() throws {
        systemSettings.values[.computerName] = .string("Old Name")
        systemSettings.failure = SystemSettingError.invalidValue
        access.hasAdministratorAccess = true
        let item = try systemItem("computerName", valueType: "string", control: #"{ "type": "text" }"#)
        item.text = "New Name"
        #expect(item.text == "Old Name")
        #expect(item.errorMessage != nil)
    }

    @Test func finderFolderShowsAFriendlyName() throws {
        systemSettings.values[.finderNewWindowTarget] = .string("file:///Volumes/Projects/")
        let item = try systemItem("finderNewWindowTarget", valueType: "string", control: #"{ "type": "folder" }"#)
        #expect(item.currentDisplayText == "/Volumes/Projects")
        #expect(item.canReset)

        item.text = FinderWindowTarget.home
        #expect(item.currentDisplayText == "Home")

        item.reset()
        #expect(systemSettings.values[.finderNewWindowTarget] == nil)
        #expect(item.currentDisplayText == "Default")
    }
}
