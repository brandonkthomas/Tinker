//
//  SettingItemTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// How a preference-backed setting reads, writes and describes its value.
@MainActor
struct SettingItemTests {
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

    @Test func plainToggleWritesBothStates() throws {
        let item = item(try preferenceSetting(control: #"{ "type": "toggle", "on": true, "off": false, "unset": "off" }"#))
        #expect(!item.isOn)
        #expect(!item.isCustomized)

        item.isOn = true
        #expect(store.values[testLocation] == .bool(true))
        #expect(item.isOn)

        item.isOn = false
        #expect(store.values[testLocation] == .bool(false))
        #expect(item.isCustomized)
    }

    /// Like Finder's `QLHidePanelOnDeactivate`: absent means on, `true` means off.
    @Test func invertedToggleIsOnWhenTheKeyIsAbsent() throws {
        let item = item(try preferenceSetting(control: #"{ "type": "toggle", "on": null, "off": true }"#))
        #expect(item.isOn)

        item.isOn = false
        #expect(store.values[testLocation] == .bool(true))
        #expect(!item.isOn)

        item.isOn = true
        #expect(store.values[testLocation] == nil)
    }

    @Test func toggleReadsValuesWrittenWithAnotherType() throws {
        store.values[testLocation] = .int(1)
        let item = item(try preferenceSetting(control: #"{ "type": "toggle", "on": true, "off": false, "unset": "off" }"#))
        #expect(item.isOn)
    }

    @Test func choiceShowsTheUnsetOptionAndWritesTheSelection() throws {
        let item = item(try preferenceSetting(valueType: "string", control: """
        { "type": "choice", "unset": "genie",
          "options": [{ "label": "Genie", "value": "genie" }, { "label": "Scale", "value": "scale" }] }
        """))
        #expect(item.selection == .string("genie"))
        #expect(!item.isCustomized)

        item.selection = .string("scale")
        #expect(store.values[testLocation] == .string("scale"))
    }

    @Test func numberIsStoredInTheSettingsValueType() throws {
        let item = item(try preferenceSetting(valueType: "intString", control: #"{ "type": "number", "min": 0, "max": 50, "step": 1, "unset": 10 }"#))
        #expect(item.number == 10)

        item.number = 9
        #expect(store.values[testLocation] == .string("9"))
        #expect(item.number == 9)
    }

    @Test func resetRemovesEveryMirroredKey() throws {
        let item = item(try preferenceSetting(
            control: #"{ "type": "toggle", "on": true, "off": false, "unset": "off" }"#,
            extra: #", "mirrorKeys": ["Key2"]"#
        ))
        let mirror = PreferenceLocation(domain: "com.example.test", key: "Key2")

        item.isOn = true
        #expect(store.values[mirror] == .bool(true))

        item.reset()
        #expect(store.values[testLocation] == nil)
        #expect(store.values[mirror] == nil)
        #expect(!item.isCustomized)
    }

    @Test func valuesReadTheWayTheControlShowsThem() throws {
        let toggle = item(try preferenceSetting(control: #"{ "type": "toggle", "on": null, "off": true }"#))
        #expect(toggle.currentDisplayText == "On")
        #expect(toggle.displayText(for: .bool(true)) == "Off")

        let choice = item(try preferenceSetting(valueType: "string", control: """
        { "type": "choice", "unset": "genie",
          "options": [{ "label": "Genie", "value": "genie" }, { "label": "Scale", "value": "scale" }] }
        """))
        #expect(choice.currentDisplayText == "Genie")
        #expect(choice.displayText(for: .string("scale")) == "Scale")

        let number = item(try preferenceSetting(valueType: "double", control: #"{ "type": "number", "min": 16, "max": 128, "step": 1, "unit": "pt" }"#))
        #expect(number.currentDisplayText == "Default")
        #expect(number.displayText(for: .int(47)) == "47 pt")
    }

    @Test func changesQueueTheRightKindOfRestart() throws {
        let item = item(try preferenceSetting(control: #"{ "type": "toggle", "on": true, "off": false, "unset": "off" }"#))
        item.isOn = true
        #expect(restartQueue.systemProcesses == ["Dock"])
        #expect(restartQueue.apps == ["Safari"])
    }
}
