//
//  AppModelTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// Sidebar contents, selection, search and the tier filter.
@MainActor
struct AppModelTests {
    let store = InMemoryPreferenceStore()

    @Test func sidebarLeavesOutCategoriesWithoutSettings() throws {
        let model = try makeSampleModel(store: store)
        #expect(model.sidebarSections.map(\.title) == ["Desktop"])
        #expect(model.sidebarSections.first?.categories.map(\.id) == ["dock", "finder"])
    }

    @Test func opensOnTheDashboard() throws {
        let model = try makeSampleModel(store: store)
        #expect(model.selection == .dashboard)
        #expect(model.detailContent == .dashboard)
    }

    @Test func selectionShowsThatCategoryGroupedInCatalogOrder() throws {
        let model = try makeSampleModel(store: store)
        model.selection = .category("dock")
        #expect(model.visibleGroups.map(\.title) == ["Behavior", "Contents"])
        #expect(model.detailContent == .settingsList)

        model.selection = .category("finder")
        #expect(model.visibleGroups.flatMap(\.items).first?.id == "finder.hidden")
        #expect(model.detailTitle == "Finder")
    }

    @Test func allSettingsListsEveryCategoryAndNamesIt() throws {
        let model = try makeSampleModel(store: store)
        model.selection = .allSettings
        #expect(model.visibleGroups.map(\.title) == ["Dock: Behavior", "Dock: Contents", "Finder: Visibility"])
        #expect(model.visibleGroups.flatMap(\.items).count == 5)
        #expect(model.detailTitle == "All Settings")
    }

    /// The real catalog lists every category's settings in the same order as the sidebar.
    @Test func allSettingsFollowsSidebarOrder() throws {
        let catalog = try Catalog.bundled()
        let model = AppModel(catalog: .success(catalog), store: store, systemSettings: FakeSystemSettings())
        model.selection = .allSettings
        var listed: [String] = []
        for item in model.visibleGroups.flatMap(\.items) where listed.last != item.definition.category {
            listed.append(item.definition.category)
        }
        #expect(listed == model.sidebarSections.flatMap(\.categories).map(\.id))
    }

    @Test func searchSpansCategoriesAndMatchesKeys() throws {
        let model = try makeSampleModel(store: store)
        model.selection = .category("dock")
        model.searchText = "AppleShowAll"
        #expect(model.selection == .allSettings)
        #expect(model.visibleGroups.map(\.title) == ["Finder: Visibility"])

        model.searchText = "dock"
        #expect(model.visibleGroups.flatMap(\.items).count == 2)
    }

    @Test func searchingFromAnyTabMovesToAllSettings() throws {
        let model = try makeSampleModel(store: store)
        model.selection = .appSettings
        #expect(model.detailContent == .appSettings)

        model.searchText = "hidden"
        #expect(model.selection == .allSettings)
        #expect(model.detailContent == .settingsList)
        #expect(model.visibleGroups.flatMap(\.items).map(\.id) == ["finder.hidden"])
    }

    @Test func choosingAnotherTabEndsTheSearch() throws {
        let model = try makeSampleModel(store: store)
        model.searchText = "hidden"

        model.selection = .category("dock")
        #expect(model.searchText.isEmpty)
        #expect(model.visibleGroups.map(\.title) == ["Behavior", "Contents"])
    }

    @Test func stayingOnAllSettingsKeepsTheSearch() throws {
        let model = try makeSampleModel(store: store)
        model.searchText = "hidden"

        model.selection = .allSettings
        #expect(model.searchText == "hidden")
    }

    @Test func viewingATierOpensAllSettingsFilteredToIt() throws {
        let model = try makeSampleModel(store: store)
        model.showAllSettings(in: .advanced)
        #expect(model.selection == .allSettings)
        #expect(model.tierFilter == .advanced)
        #expect(model.visibleGroups.flatMap(\.items).map(\.id) == ["dock.static"])
    }

    @Test func tierFilterNarrowsTheSelectedCategory() throws {
        let model = try makeSampleModel(store: store)
        model.selection = .category("dock")
        model.tierFilter = .advanced
        #expect(model.visibleGroups.flatMap(\.items).map(\.id) == ["dock.static"])
    }

    @Test func aBrokenCatalogIsReportedInsteadOfCrashing() {
        let model = AppModel(catalog: .failure(CatalogError.missingResource), store: InMemoryPreferenceStore())
        #expect(model.loadError != nil)
        #expect(model.sidebarSections.isEmpty)
    }
}
