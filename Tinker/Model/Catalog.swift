//
//  Catalog.swift
//  Tinker
//
//  The types decoded from Resources/Catalog.json. The JSON file is the
//  single list of every setting Tinker knows about.
//

import Foundation

nonisolated struct Catalog: Decodable, Sendable {
    let version: Int
    let categories: [SettingCategory]
    let settings: [SettingDefinition]

    static func load(from url: URL) throws -> Catalog {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        try catalog.validate()
        return catalog
    }

    static func bundled() throws -> Catalog {
        guard let url = Bundle.main.url(forResource: "Catalog", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try load(from: url)
    }

    /// Catches catalog mistakes at load time instead of as wrong behavior in a row.
    func validate() throws {
        let categoryIDs = Set(categories.map(\.id))
        var seen = Set<String>()
        for setting in settings {
            guard seen.insert(setting.id).inserted else {
                throw CatalogError.invalid(setting: setting.id, reason: "duplicate id")
            }
            guard categoryIDs.contains(setting.category) else {
                throw CatalogError.invalid(setting: setting.id, reason: "unknown category \(setting.category)")
            }
            for value in setting.control.catalogValues where value.coerced(to: setting.valueType) == nil {
                throw CatalogError.invalid(
                    setting: setting.id,
                    reason: "\(value.displayText) is not a valid \(setting.valueType.rawValue)"
                )
            }
            if case .toggle(let on, let off, _) = setting.control,
               on?.coerced(to: setting.valueType) == off?.coerced(to: setting.valueType) {
                throw CatalogError.invalid(setting: setting.id, reason: "on and off are the same value")
            }
        }
    }
}

nonisolated enum CatalogError: LocalizedError {
    case missingResource
    case invalid(setting: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            String(localized: "Catalog.json is missing from the app bundle.")
        case .invalid(let setting, let reason):
            String(localized: "Catalog entry \(setting) is invalid: \(reason).")
        }
    }
}

nonisolated struct SettingCategory: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Sidebar section heading this category is listed under.
    let section: String
    /// SF Symbol name.
    let symbol: String
    let color: String
}

/// Who a setting is for. Independent of its category.
nonisolated enum Tier: String, Decodable, CaseIterable, Identifiable, Sendable {
    /// Any developer would want it.
    case recommended
    /// Taste, or a value specific to one Mac.
    case personal
    /// A hidden preference where the system default suits most people.
    case advanced

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .recommended: "Recommended"
        case .personal: "Personal"
        case .advanced: "Advanced"
        }
    }
}

nonisolated struct SettingDefinition: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let category: String
    let group: String
    let title: String
    let detail: String?
    let tier: Tier
    /// Where the value lives: a preference key, or a built-in system setting.
    let backing: Backing
    let valueType: ValueType
    let control: SettingControl
    /// Processes that must restart before a change shows.
    let restart: [String]
    /// True when the preference lives in a sandboxed app's container.
    let needsFullDiskAccess: Bool
    /// The value this setting's tier profile writes, if it is part of one.
    let profileValue: PreferenceValue?

    enum Backing: Equatable, Sendable {
        case preference(Store)
        case system(SystemSetting)
    }

    /// The preference this setting is stored in, if it is one.
    var store: Store? {
        if case .preference(let store) = backing { store } else { nil }
    }

    var systemSetting: SystemSetting? {
        if case .system(let setting) = backing { setting } else { nil }
    }

    /// Every preference key this setting writes, primary key first. Empty for a system setting.
    var preferenceLocations: [PreferenceLocation] {
        guard let store else { return [] }
        return store.locations.map { location in
            var location = location
            // The apps that need Full Disk Access are the sandboxed ones.
            location.isInAppContainer = needsFullDiskAccess
            return location
        }
    }

    /// Changing it needs root: a system-wide preference, or a system command.
    var needsAdministrator: Bool {
        switch backing {
        case .preference(let store): store.scope == .system
        case .system(let setting): setting.needsAdministrator
        }
    }

    /// The preference domain and key, or the tool behind a system setting.
    var technicalName: String {
        switch backing {
        case .preference(let store): "\(store.domain)  \(store.key)"
        case .system(let setting): setting.technicalName
        }
    }

    struct Store: Decodable, Equatable, Sendable {
        let domain: String
        let key: String
        /// Extra keys that always receive the same value as `key`.
        let mirrorKeys: [String]
        let host: PreferenceLocation.Host
        let scope: PreferenceLocation.Scope

        private enum CodingKeys: String, CodingKey {
            case domain, key, mirrorKeys, host, scope
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            domain = try container.decode(String.self, forKey: .domain)
            key = try container.decode(String.self, forKey: .key)
            mirrorKeys = try container.decodeIfPresent([String].self, forKey: .mirrorKeys) ?? []
            host = try container.decodeIfPresent(PreferenceLocation.Host.self, forKey: .host) ?? .any
            scope = try container.decodeIfPresent(PreferenceLocation.Scope.self, forKey: .scope) ?? .user
        }

        /// The primary key first, then any mirror keys.
        var locations: [PreferenceLocation] {
            ([key] + mirrorKeys).map {
                PreferenceLocation(domain: domain, key: $0, host: host, scope: scope)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, category, group, title, detail, tier, store, system, valueType, control
        case restart, needsFullDiskAccess, profileValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(String.self, forKey: .category)
        group = try container.decode(String.self, forKey: .group)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        tier = try container.decode(Tier.self, forKey: .tier)
        if let setting = try container.decodeIfPresent(SystemSetting.self, forKey: .system) {
            backing = .system(setting)
        } else {
            backing = .preference(try container.decode(Store.self, forKey: .store))
        }
        valueType = try container.decode(ValueType.self, forKey: .valueType)
        control = try container.decode(SettingControl.self, forKey: .control)
        restart = try container.decodeIfPresent([String].self, forKey: .restart) ?? []
        needsFullDiskAccess = try container.decodeIfPresent(Bool.self, forKey: .needsFullDiskAccess) ?? false
        profileValue = try container.decodeIfPresent(PreferenceValue.self, forKey: .profileValue)
    }
}

/// The kind of control a setting is edited with, and what its states mean.
nonisolated enum SettingControl: Decodable, Equatable, Sendable {
    /// `on` and `off` are the values written for each state. `nil` means
    /// "remove the key". `unsetIsOn` says which state an absent key shows as.
    case toggle(on: PreferenceValue?, off: PreferenceValue?, unsetIsOn: Bool)
    /// `unset` is the option an absent key shows as.
    case choice(options: [Option], unset: PreferenceValue?)
    /// `unset` is the value an absent key shows as, when it is known.
    case number(range: ClosedRange<Double>, step: Double, unit: String?, unset: Double?)
    case text(placeholder: String?)
    /// A yes/no state that is reported rather than switched, with buttons
    /// for what can be done about it. Used by system settings.
    case status(onLabel: String, offLabel: String, actions: [StatusAction])
    /// A folder: one of a few standard ones, or any folder the user picks.
    case folder

    struct Option: Decodable, Hashable, Sendable {
        let label: String
        let value: PreferenceValue
    }

    /// A button on a status row. Pressing it asks for the state `value`.
    struct StatusAction: Decodable, Hashable, Sendable {
        enum Visibility: String, Decodable, Sendable {
            case on, off, always
        }

        let title: String
        let value: Bool
        /// Which current state the button is offered in.
        let when: Visibility
    }

    private enum CodingKeys: String, CodingKey {
        case type, on, off, unset, options, min, max, step, unit, placeholder
        case onLabel, offLabel, actions
    }

    private enum Kind: String, Decodable {
        case toggle, choice, number, text, status, folder
    }

    private enum ToggleState: String, Decodable {
        case on, off
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .toggle:
            let on = try container.decodeIfPresent(PreferenceValue.self, forKey: .on)
            let off = try container.decodeIfPresent(PreferenceValue.self, forKey: .off)
            let unsetIsOn: Bool
            if let state = try container.decodeIfPresent(ToggleState.self, forKey: .unset) {
                unsetIsOn = state == .on
            } else if on == nil {
                unsetIsOn = true
            } else if off == nil {
                unsetIsOn = false
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .unset, in: container,
                    debugDescription: "A toggle with both on and off values must say which one an absent key means."
                )
            }
            self = .toggle(on: on, off: off, unsetIsOn: unsetIsOn)
        case .choice:
            self = .choice(
                options: try container.decode([Option].self, forKey: .options),
                unset: try container.decodeIfPresent(PreferenceValue.self, forKey: .unset)
            )
        case .number:
            let lower = try container.decode(Double.self, forKey: .min)
            let upper = try container.decode(Double.self, forKey: .max)
            guard lower < upper else {
                throw DecodingError.dataCorruptedError(
                    forKey: .max, in: container, debugDescription: "max must be greater than min."
                )
            }
            self = .number(
                range: lower...upper,
                step: try container.decode(Double.self, forKey: .step),
                unit: try container.decodeIfPresent(String.self, forKey: .unit),
                unset: try container.decodeIfPresent(Double.self, forKey: .unset)
            )
        case .text:
            self = .text(placeholder: try container.decodeIfPresent(String.self, forKey: .placeholder))
        case .status:
            self = .status(
                onLabel: try container.decode(String.self, forKey: .onLabel),
                offLabel: try container.decode(String.self, forKey: .offLabel),
                actions: try container.decodeIfPresent([StatusAction].self, forKey: .actions) ?? []
            )
        case .folder:
            self = .folder
        }
    }

    /// Every preference value the catalog entry names, for validation.
    var catalogValues: [PreferenceValue] {
        switch self {
        case .toggle(let on, let off, _): [on, off].compactMap(\.self)
        case .choice(let options, let unset): options.map(\.value) + [unset].compactMap(\.self)
        case .number, .text, .status, .folder: []
        }
    }
}
