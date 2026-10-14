//
//  SettingsDetailView.swift
//  Tinker
//

import SwiftUI

struct SettingsDetailView: View {
    let groups: [SettingGroup]
    let title: String
    let isSearching: Bool

    var body: some View {
        // A grouped Form builds every row up front, which made All Settings
        // slow to open. A lazy stack builds a group only when it scrolls into view.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(groups) { group in
                    SettingGroupSection(title: group.title, items: group.items)
                }
            }
            .padding(20)
        }
        .overlay {
            if groups.isEmpty {
                EmptySettingsView(isSearching: isSearching)
            }
        }
        .navigationTitle(title)
    }
}

struct EmptySettingsView: View {
    let isSearching: Bool

    var body: some View {
        if isSearching {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView(
                "No Settings",
                systemImage: "slider.horizontal.3",
                description: Text("No settings here belong to the selected profile.")
            )
        }
    }
}

struct SettingGroupSection: View {
    let title: String
    let items: [SettingItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 10)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    SettingRow(item: item, showsDivider: item.id != items.last?.id)
                }
            }
            .background(.fill.quaternary, in: .rect(cornerRadius: 10))
        }
    }
}

struct SettingRow: View {
    let item: SettingItem
    /// Draws the line that separates this row from the one below it.
    let showsDivider: Bool

    var body: some View {
        HStack(spacing: 12) {
            SettingLabel(
                title: item.definition.title,
                detail: item.definition.detail,
                technicalName: item.definition.technicalName,
                tier: item.definition.tier,
                blocker: item.blocker,
                errorMessage: item.errorMessage
            )
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if item.isReadable {
                    ResetButton(item: item)
                    SettingControlView(item: item)
                        .disabled(!item.isEditable)
                } else {
                    // The value cannot be read, so showing a switch would state something unknown.
                    Text("Unknown")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.horizontal, 10)
                .opacity(showsDivider ? 1 : 0)
        }
    }
}

struct SettingLabel: View {
    let title: String
    let detail: String?
    /// The preference domain and key, or the tool behind a system setting.
    let technicalName: String
    let tier: Tier
    let blocker: SettingItem.Blocker?
    let errorMessage: String?

    @Environment(\.showsPreferenceKeys) private var showsPreferenceKeys

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                if let detail {
                    InfoButton(text: Text(detail))
                }
                TierBadge(tier: tier)
                if let blocker {
                    BlockerIcon(blocker: blocker)
                }
            }
            if showsPreferenceKeys {
                Text(verbatim: technicalName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct BlockerIcon: View {
    let blocker: SettingItem.Blocker

    var body: some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.orange)
            .hoverPopover(explanation)
            .accessibilityLabel(Text(blocker.title))
    }

    private var symbol: String {
        switch blocker {
        case .fullDiskAccess: "externaldrive.badge.questionmark"
        case .administratorAccess: "lock.fill"
        }
    }

    private var explanation: LocalizedStringKey {
        switch blocker {
        case .fullDiskAccess: "This app keeps its settings in a protected folder. Allow Full Disk Access in Tinker's Settings to read or change this."
        case .administratorAccess: "Needs administrator access. Turn it on in Tinker's Settings to change this."
        }
    }
}

struct TierBadge: View {
    let tier: Tier

    var body: some View {
        Badge(text: tier.title, color: tier.color)
    }
}

struct Badge: View {
    let text: LocalizedStringResource
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: .capsule)
    }
}

/// Removes the stored value. Stays in the layout when there is nothing to
/// reset so controls do not shift sideways.
struct ResetButton: View {
    let item: SettingItem

    var body: some View {
        Button("Reset to Default", systemImage: "arrow.uturn.backward", action: item.reset)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .hoverPopover("Remove this value and use the system default")
            .opacity(item.canReset ? 1 : 0)
            .disabled(!item.canReset)
    }
}
