//
//  TestSupport.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// Keeps values in memory so tests never touch real preferences.
final class InMemoryPreferenceStore: PreferenceStore, @unchecked Sendable {
    var values: [PreferenceLocation: PreferenceValue] = [:]
    /// Stands in for the privileged helper being enabled.
    var allowsSystemWrites = false

    func value(at location: PreferenceLocation) -> PreferenceValue? {
        values[location]
    }

    func setValue(_ value: PreferenceValue?, at location: PreferenceLocation) throws {
        guard location.scope == .user || allowsSystemWrites else { throw PreferenceError.needsAdministrator }
        values[location] = value
    }
}

/// Stands in for the system tools, so tests never run or change anything real.
final class FakeSystemSettings: SystemSettingsProviding, @unchecked Sendable {
    var values: [SystemSetting: PreferenceValue] = [:]
    var failure: (any Error)?

    func value(of setting: SystemSetting) -> PreferenceValue? {
        values[setting]
    }

    func setValue(_ value: PreferenceValue?, for setting: SystemSetting) throws {
        if let failure { throw failure }
        values[setting] = value
    }
}

/// Decodes one catalog entry from JSON.
func settingDefinition(_ json: String) throws -> SettingDefinition {
    try JSONDecoder().decode(SettingDefinition.self, from: Data(json.utf8))
}

/// A preference-backed setting stored at `testLocation`, with the given control.
func preferenceSetting(valueType: String = "bool", control: String, extra: String = "") throws -> SettingDefinition {
    try settingDefinition("""
    {
      "id": "test.setting", "category": "test", "group": "Group", "title": "Title", "tier": "advanced",
      "store": { "domain": "com.example.test", "key": "Key" \(extra) },
      "valueType": "\(valueType)", "control": \(control), "restart": ["Dock", "Safari"]
    }
    """)
}

let testLocation = PreferenceLocation(domain: "com.example.test", key: "Key")

/// An app model over a small catalog: two Dock settings (personal, advanced)
/// and three Finder settings (recommended, one of them administrator-only),
/// plus a category with no settings.
@MainActor
func makeSampleModel(store: InMemoryPreferenceStore) throws -> AppModel {
    let catalog = try JSONDecoder().decode(Catalog.self, from: Data("""
    {
      "version": 1,
      "categories": [
        { "id": "dock", "title": "Dock", "section": "Desktop", "symbol": "dock.rectangle", "color": "teal" },
        { "id": "finder", "title": "Finder", "section": "Desktop", "symbol": "folder", "color": "cyan" },
        { "id": "empty", "title": "Empty", "section": "Other", "symbol": "gear", "color": "gray" }
      ],
      "settings": [
        { "id": "dock.autohide", "category": "dock", "group": "Behavior", "title": "Hide the Dock", "tier": "personal",
          "store": { "domain": "com.apple.dock", "key": "autohide" }, "valueType": "bool",
          "control": { "type": "toggle", "on": true, "off": false, "unset": "off" }, "profileValue": true },
        { "id": "dock.static", "category": "dock", "group": "Contents", "title": "Only open apps", "tier": "advanced",
          "store": { "domain": "com.apple.dock", "key": "static-only" }, "valueType": "bool",
          "control": { "type": "toggle", "on": true, "off": null } },
        { "id": "finder.hidden", "category": "finder", "group": "Visibility", "title": "Show hidden files", "tier": "recommended",
          "store": { "domain": "com.apple.finder", "key": "AppleShowAllFiles" }, "valueType": "bool",
          "control": { "type": "toggle", "on": true, "off": false, "unset": "off" }, "profileValue": true },
        { "id": "finder.warning", "category": "finder", "group": "Visibility", "title": "Extension warning", "tier": "recommended",
          "store": { "domain": "com.apple.finder", "key": "FXEnableExtensionChangeWarning" }, "valueType": "bool",
          "control": { "type": "toggle", "on": true, "off": false, "unset": "on" }, "profileValue": false },
        { "id": "finder.guest", "category": "finder", "group": "Visibility", "title": "Guest account", "tier": "recommended",
          "store": { "domain": "com.apple.loginwindow", "key": "GuestEnabled", "scope": "system" }, "valueType": "bool",
          "control": { "type": "toggle", "on": true, "off": false, "unset": "off" }, "profileValue": false }
      ]
    }
    """.utf8))
    return AppModel(catalog: .success(catalog), store: store)
}
