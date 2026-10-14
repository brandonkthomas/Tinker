//
//  Profile.swift
//  Tinker
//

import Foundation

/// A tier's settings, with the value each one should have where the
/// catalog gives one (`profileValue`). Only Recommended has such values;
/// Personal and Advanced are matters of taste, so they can be viewed but
/// have nothing to apply.
struct Profile: Identifiable, Equatable {
    struct Entry: Identifiable {
        let item: SettingItem
        let value: PreferenceValue
        /// "Category: Group", for listing entries under headings.
        let groupTitle: String

        var id: String { item.id }
    }

    let tier: Tier
    /// How many settings the tier has, with or without a profile value.
    let settingCount: Int
    let entries: [Entry]

    var id: Tier { tier }

    static func == (lhs: Profile, rhs: Profile) -> Bool {
        lhs.tier == rhs.tier && lhs.settingCount == rhs.settingCount && lhs.entries.map(\.id) == rhs.entries.map(\.id)
    }

    var title: LocalizedStringResource { tier.title }

    var summary: LocalizedStringResource {
        switch tier {
        case .recommended: "Settings intended for developer workflows (visible files and extensions, Finder path bar, safer defaults)."
        case .personal: "Personal preference items (Dock, appearance, menu bar clock and keyboard)."
        case .advanced: "Hidden macOS preferences."
        }
    }

    var symbol: String {
        switch tier {
        case .recommended: "checkmark.seal.fill"
        case .personal: "person.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        }
    }

    /// False when the tier has no preset values, so there is nothing to review or apply.
    var canApply: Bool { !entries.isEmpty }

    /// Entries whose setting does not have the profile's value yet and can be changed here.
    var pendingEntries: [Entry] {
        entries.filter { $0.item.isEditable && $0.item.canApplyInBulk && !$0.item.matches($0.value) }
    }

    /// Entries Tinker cannot change yet: either the value differs and a
    /// permission is missing, or the value cannot be read at all.
    var blockedEntries: [Entry] {
        entries.filter { !($0.item.isEditable && $0.item.canApplyInBulk) && !$0.item.matches($0.value) }
    }

    var appliedCount: Int {
        entries.count { $0.item.matches($0.value) }
    }

    /// Applies the pending entries whose ids are in `selectedIDs`.
    func apply(only selectedIDs: Set<Entry.ID>) {
        for entry in pendingEntries where selectedIDs.contains(entry.id) {
            entry.item.apply(entry.value)
        }
    }

    func apply() {
        apply(only: Set(entries.map(\.id)))
    }
}
