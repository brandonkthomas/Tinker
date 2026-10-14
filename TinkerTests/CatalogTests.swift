//
//  CatalogTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

struct CatalogTests {
    @Test func bundledCatalogLoadsAndValidates() throws {
        let catalog = try Catalog.bundled()
        #expect(catalog.settings.count > 100)
        #expect(Set(catalog.settings.map(\.category)).isSubset(of: Set(catalog.categories.map(\.id))))
    }

    /// Personal and Advanced settings are taste, so only Recommended ones carry a preset value.
    @Test func onlyRecommendedSettingsHavePresetValues() throws {
        let preset = try Catalog.bundled().settings.filter { $0.profileValue != nil }
        #expect(!preset.isEmpty)
        #expect(preset.allSatisfy { $0.tier == .recommended })
    }

    /// The settings that came from the deploy script and are not preference keys.
    @Test func bundledCatalogIncludesTheSystemSettings() throws {
        let present = Set(try Catalog.bundled().settings.compactMap(\.systemSetting))
        #expect(present == Set(SystemSetting.allCases))
    }

    @Test func toggleNeedsToKnowWhatAnAbsentKeyMeans() {
        #expect(throws: DecodingError.self) {
            try preferenceSetting(control: #"{ "type": "toggle", "on": true, "off": false }"#)
        }
    }

    @Test func validationRejectsValuesOfTheWrongType() throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data("""
        {
          "version": 1,
          "categories": [{ "id": "test", "title": "Test", "section": "S", "symbol": "gear", "color": "gray" }],
          "settings": [{
            "id": "test.bad", "category": "test", "group": "G", "title": "T", "tier": "advanced",
            "store": { "domain": "d", "key": "k" }, "valueType": "int",
            "control": { "type": "choice", "options": [{ "label": "Genie", "value": "genie" }] }
          }]
        }
        """.utf8))
        #expect(throws: CatalogError.self) { try catalog.validate() }
    }
}
