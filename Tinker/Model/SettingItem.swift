//
//  SettingItem.swift
//  Tinker
//

import Foundation
import Observation

/// One catalog setting together with its current value on this Mac.
/// Rows observe their own item, so changing one setting redraws one row.
@Observable
final class SettingItem: Identifiable {
    let definition: SettingDefinition

    /// The stored value, expressed in the setting's value type.
    /// `nil` means the key is absent and the system default applies.
    private(set) var storedValue: PreferenceValue?
    private(set) var errorMessage: String?

    private let store: any PreferenceStore
    private let systemSettings: any SystemSettingsProviding
    private let restartQueue: RestartQueue
    private let access: AccessStatus

    init(definition: SettingDefinition, store: any PreferenceStore, systemSettings: any SystemSettingsProviding,
         restartQueue: RestartQueue, access: AccessStatus) {
        self.definition = definition
        self.store = store
        self.systemSettings = systemSettings
        self.restartQueue = restartQueue
        self.access = access
        reload()
    }

    var id: String { definition.id }

    /// True when a value is stored, so there is something to reset.
    var isCustomized: Bool { storedValue != nil }

    /// Whether "reset" means anything here. A preference can always go back
    /// to the system default; most system settings have no such thing.
    var canReset: Bool {
        isCustomized && isEditable && (definition.systemSetting?.supportsReset ?? true)
    }

    /// False for settings that are only reported, or that open something
    /// the user must finish. Those are never changed by applying a profile.
    var canApplyInBulk: Bool {
        guard let setting = definition.systemSetting else { return true }
        return !setting.isReadOnly && !setting.isInteractive
    }

    /// A permission Tinker is missing for this setting.
    enum Blocker: Equatable {
        /// The preference is in another app's container; without access its value is unknown.
        case fullDiskAccess
        /// The preference is system-wide and the privileged helper is off.
        case administratorAccess

        var title: LocalizedStringResource {
            switch self {
            case .fullDiskAccess: "Needs Full Disk Access"
            case .administratorAccess: "Needs administrator access"
            }
        }
    }

    /// What stops this setting from being changed right now, if anything.
    var blocker: Blocker? {
        if definition.needsFullDiskAccess, !access.hasFullDiskAccess { return .fullDiskAccess }
        if definition.needsAdministrator, !access.hasAdministratorAccess { return .administratorAccess }
        return nil
    }

    /// False when the current value cannot be read, so the row must not pretend to know it.
    var isReadable: Bool { blocker != .fullDiskAccess }

    var isEditable: Bool { blocker == nil }

    func reload() {
        guard isReadable else {
            storedValue = nil
            return
        }
        switch definition.backing {
        case .preference:
            storedValue = definition.preferenceLocations.first.flatMap { store.value(at: $0) }.flatMap(coerced)
        case .system(let setting):
            storedValue = systemSettings.value(of: setting).flatMap(coerced)
        }
    }

    /// Takes a value that was read elsewhere, so many system settings can
    /// be read together off the main thread.
    func update(systemValue: PreferenceValue?) {
        guard definition.systemSetting != nil, isReadable else { return }
        storedValue = systemValue.flatMap(coerced)
    }

    /// Removes the key so the system default applies again.
    func reset() {
        write(nil)
    }

    // MARK: Control state

    var isOn: Bool {
        get {
            guard case .toggle(_, _, let unsetIsOn) = definition.control else { return false }
            guard let storedValue else { return unsetIsOn }
            return toggleState(for: storedValue)
        }
        set {
            guard case .toggle(let on, let off, _) = definition.control else { return }
            write(newValue ? on : off)
        }
    }

    /// The selected option's value. An absent key shows the catalog's `unset` option.
    var selection: PreferenceValue? {
        get {
            guard case .choice(_, let unset) = definition.control else { return nil }
            return storedValue ?? unset.flatMap(coerced)
        }
        set {
            write(newValue)
        }
    }

    /// The numeric value, or `nil` when the key is absent and the default is not known.
    var number: Double? {
        get {
            guard case .number(_, _, _, let unset) = definition.control else { return nil }
            return storedValue?.doubleValue ?? unset
        }
        set {
            write(newValue.map(PreferenceValue.double))
        }
    }

    var text: String {
        get {
            if case .string(let value) = storedValue { value } else { "" }
        }
        set {
            write(newValue.isEmpty ? nil : .string(newValue))
        }
    }

    /// The state a status row reports, or `nil` when it could not be determined.
    var statusIsOn: Bool? {
        if case .bool(let isOn) = storedValue { isOn } else { nil }
    }

    // MARK: Profiles

    /// True when the setting already behaves as if `target` were stored.
    /// An absent key counts when the system default is the same state.
    func matches(_ target: PreferenceValue) -> Bool {
        guard isReadable, let target = coerced(target) else { return false }
        if case .toggle = definition.control {
            return isOn == toggleState(for: target)
        }
        return (storedValue ?? unsetValue) == target
    }

    func apply(_ value: PreferenceValue) {
        write(value)
    }

    /// The current state in words, for example "On", "Scale effect" or "47 pt".
    var currentDisplayText: String {
        displayText(for: storedValue ?? unsetValue)
    }

    /// How `value` reads in this setting's control. `nil` is the system default.
    func displayText(for value: PreferenceValue?) -> String {
        guard let value = value.flatMap(coerced) else {
            switch definition.control {
            case .toggle(_, _, let unsetIsOn):
                return unsetIsOn ? String(localized: "On") : String(localized: "Off")
            case .status:
                return String(localized: "Unknown")
            case .text where definition.systemSetting != nil:
                return String(localized: "Not set")
            default:
                return String(localized: "Default")
            }
        }
        switch definition.control {
        case .toggle:
            return toggleState(for: value) ? String(localized: "On") : String(localized: "Off")
        case .choice(let options, _):
            return options.first { coerced($0.value) == value }?.label ?? value.displayText
        case .number(_, _, let unit, _):
            let number = (value.doubleValue ?? 0).formatted(.number.precision(.fractionLength(0...2)))
            return unit.map { "\(number) \($0)" } ?? number
        case .text:
            return value.displayText
        case .status(let onLabel, let offLabel, _):
            return value == .bool(true) ? onLabel : offLabel
        case .folder:
            return FinderWindowTarget.displayName(for: value.displayText)
        }
    }

    // MARK: Private

    /// Which toggle state a stored value stands for.
    private func toggleState(for value: PreferenceValue) -> Bool {
        guard case .toggle(let on, let off, _) = definition.control else { return false }
        if let on { return value == coerced(on) }
        return value != off.flatMap(coerced)
    }

    /// The value an absent key behaves as, when the catalog knows it.
    private var unsetValue: PreferenceValue? {
        let value: PreferenceValue? = switch definition.control {
        case .toggle(let on, let off, let unsetIsOn): unsetIsOn ? on : off
        case .choice(_, let unset): unset
        case .number(_, _, _, let unset): unset.map(PreferenceValue.double)
        case .text, .status, .folder: nil
        }
        return value.flatMap(coerced)
    }

    private func coerced(_ value: PreferenceValue) -> PreferenceValue? {
        value.coerced(to: definition.valueType)
    }

    private func write(_ value: PreferenceValue?) {
        let typedValue = value.flatMap(coerced)
        // A value that cannot be expressed in the setting's type must not
        // fall through as `nil`, which would delete the key instead.
        guard (value == nil) == (typedValue == nil) else {
            errorMessage = String(localized: "That value is not valid for this setting.")
            return
        }
        if let blocker {
            errorMessage = String(localized: blocker.title)
            return
        }
        do {
            switch definition.backing {
            case .preference:
                for location in definition.preferenceLocations {
                    try store.setValue(typedValue, at: location)
                }
            case .system(let setting):
                try systemSettings.setValue(typedValue, for: setting)
            }
            errorMessage = nil
            restartQueue.add(definition.restart)
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }
}
