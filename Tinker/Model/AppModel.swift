//
//  AppModel.swift
//  Tinker
//

import Foundation
import Observation

/// What the sidebar can show in the detail pane.
enum SidebarDestination: Hashable {
    case dashboard
    case allSettings
    case category(SettingCategory.ID)
    case appSettings
}

/// Categories listed under one sidebar heading.
struct SidebarSection: Identifiable, Equatable {
    let title: String
    let categories: [SettingCategory]

    var id: String { title }
}

/// Settings shown together under one heading in the detail pane.
struct SettingGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [SettingItem]

    static func == (lhs: SettingGroup, rhs: SettingGroup) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.items.map(\.id) == rhs.items.map(\.id)
    }
}

@Observable
final class AppModel {
    /// Which kind of content fills the detail pane.
    enum DetailContent: Equatable {
        case dashboard
        case settingsList
        case appSettings
    }

    let restartQueue = RestartQueue()
    let access: AccessStatus
    let helper: PrivilegedHelper
    private(set) var sidebarSections: [SidebarSection] = []
    private(set) var profiles: [Profile] = []
    /// Set when the catalog could not be loaded; the window shows it instead of settings.
    private(set) var loadError: String?

    /// `nil` only while the sidebar has nothing selected; treated as the dashboard.
    var selection: SidebarDestination? = .dashboard {
        didSet {
            // Search belongs to All Settings, so leaving that tab ends the search.
            if selection != .allSettings, isSearching { searchText = "" }
            recomputeVisibleGroups()
        }
    }

    var searchText = "" {
        didSet {
            // Typing a search from any tab shows the results in All Settings.
            if isSearching, selection != .allSettings { selection = .allSettings }
            recomputeVisibleGroups()
        }
    }

    /// `nil` shows every tier.
    var tierFilter: Tier? {
        didSet { recomputeVisibleGroups() }
    }

    /// What the settings list shows, prepared here so views do no filtering.
    private(set) var visibleGroups: [SettingGroup] = []
    private(set) var detailTitle = ""

    private var categories: [SettingCategory] = []
    private var items: [SettingItem] = []
    private let systemSettings: any SystemSettingsProviding
    private let usesSystemPermissions: Bool

    init(catalog: Result<Catalog, any Error> = Result { try Catalog.bundled() },
         store: (any PreferenceStore)? = nil,
         systemSettings: (any SystemSettingsProviding)? = nil,
         access: AccessStatus = AccessStatus()) {
        self.access = access
        let helper = PrivilegedHelper(access: access)
        self.helper = helper
        // A custom store is a test double; only the real one asks macOS what Tinker may do.
        usesSystemPermissions = store == nil
        let store = store ?? SystemPreferenceStore(privilegedWriter: helper.connection)
        let systemSettings = systemSettings ?? LiveSystemSettings(privilegedWriter: helper.connection)
        self.systemSettings = systemSettings
        if usesSystemPermissions {
            helper.refresh()
            access.hasFullDiskAccess = FullDiskAccess.isGranted
        }
        switch catalog {
        case .success(let catalog):
            categories = catalog.categories
            // List settings in sidebar order, whatever order the file has them in.
            let categoryOrder = Dictionary(uniqueKeysWithValues: catalog.categories.enumerated().map { ($1.id, $0) })
            let orderedSettings = catalog.settings.enumerated().sorted { first, second in
                let firstRank = categoryOrder[first.element.category] ?? .max
                let secondRank = categoryOrder[second.element.category] ?? .max
                return firstRank == secondRank ? first.offset < second.offset : firstRank < secondRank
            }.map(\.element)
            items = orderedSettings.map {
                SettingItem(
                    definition: $0, store: store, systemSettings: systemSettings,
                    restartQueue: restartQueue, access: access
                )
            }
            sidebarSections = Self.sidebarSections(for: catalog)
            profiles = Self.profiles(for: items, categories: catalog.categories)
            recomputeVisibleGroups()
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var detailContent: DetailContent {
        switch selection ?? .dashboard {
        case .dashboard: .dashboard
        case .allSettings, .category: .settingsList
        case .appSettings: .appSettings
        }
    }

    /// Opens All Settings showing only one tier.
    func showAllSettings(in tier: Tier) {
        tierFilter = tier
        selection = .allSettings
    }

    /// Picks up changes made outside Tinker, for example in System Settings.
    func reloadValues() {
        if usesSystemPermissions {
            helper.refresh()
            access.hasFullDiskAccess = FullDiskAccess.isGranted
        }
        for item in items where item.definition.systemSetting == nil {
            item.reload()
        }
        reloadSystemSettings()
    }

    // MARK: Private

    /// System settings are read by running small tools, so they are read
    /// together off the main thread and handed back to their rows.
    private func reloadSystemSettings() {
        let systemItems = items.filter { $0.definition.systemSetting != nil }
        let settings = systemItems.compactMap(\.definition.systemSetting)
        guard !settings.isEmpty else { return }
        let provider = systemSettings
        Task {
            let values = await Task.detached {
                settings.map { provider.value(of: $0) }
            }.value
            for (item, value) in zip(systemItems, values) {
                item.update(systemValue: value)
            }
        }
    }

    /// Sections in the order their first category appears in the catalog.
    /// Categories without settings are left out.
    private static func sidebarSections(for catalog: Catalog) -> [SidebarSection] {
        let used = Set(catalog.settings.map(\.category))
        var titles: [String] = []
        var bySection: [String: [SettingCategory]] = [:]
        for category in catalog.categories where used.contains(category.id) {
            if bySection[category.section] == nil { titles.append(category.section) }
            bySection[category.section, default: []].append(category)
        }
        return titles.map { SidebarSection(title: $0, categories: bySection[$0] ?? []) }
    }

    /// One profile per tier that has settings.
    private static func profiles(for items: [SettingItem], categories: [SettingCategory]) -> [Profile] {
        let categoryTitles = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.title) })
        return Tier.allCases.compactMap { tier in
            let tierItems = items.filter { $0.definition.tier == tier }
            guard !tierItems.isEmpty else { return nil }
            let entries = tierItems.compactMap { item -> Profile.Entry? in
                guard let value = item.definition.profileValue else { return nil }
                let definition = item.definition
                let categoryTitle = categoryTitles[definition.category] ?? definition.category
                return Profile.Entry(item: item, value: value, groupTitle: "\(categoryTitle): \(definition.group)")
            }
            return Profile(tier: tier, settingCount: tierItems.count, entries: entries)
        }
    }

    private func recomputeVisibleGroups() {
        // A search only exists while All Settings is selected.
        let query = selection == .allSettings ? searchText.trimmingCharacters(in: .whitespaces) : ""
        let selectedCategory: SettingCategory.ID? =
            if case .category(let id) = selection { id } else { nil }
        let spansCategories = selectedCategory == nil

        let matching = items.filter { item in
            let definition = item.definition
            if let tierFilter, definition.tier != tierFilter { return false }
            if let selectedCategory { return definition.category == selectedCategory }
            if query.isEmpty { return true }
            return definition.title.localizedStandardContains(query)
                || definition.group.localizedStandardContains(query)
                || definition.technicalName.localizedStandardContains(query)
        }

        let categoryTitles = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.title) })
        // Catalog order is the display order, so groups keep first-seen order.
        var order: [String] = []
        var itemsByGroup: [String: [SettingItem]] = [:]
        var titles: [String: String] = [:]
        for item in matching {
            let definition = item.definition
            let groupID = "\(definition.category)/\(definition.group)"
            if itemsByGroup[groupID] == nil {
                order.append(groupID)
                let categoryTitle = categoryTitles[definition.category] ?? definition.category
                // Say where each group comes from when the list mixes categories.
                titles[groupID] = spansCategories ? "\(categoryTitle): \(definition.group)" : definition.group
            }
            itemsByGroup[groupID, default: []].append(item)
        }

        visibleGroups = order.map {
            SettingGroup(id: $0, title: titles[$0] ?? "", items: itemsByGroup[$0] ?? [])
        }
        detailTitle = selectedCategory.flatMap { categoryTitles[$0] } ?? String(localized: "All Settings")
    }
}
