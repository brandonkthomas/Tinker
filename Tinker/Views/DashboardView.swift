//
//  DashboardView.swift
//  Tinker
//

import SwiftUI

struct DashboardView: View {
    let profiles: [Profile]
    let access: AccessStatus
    let helper: PrivilegedHelper
    /// Opens All Settings filtered to one tier.
    let viewTier: (Tier) -> Void

    @State private var reviewedProfile: Profile?
    /// Decided once when the dashboard appears. If a permission is granted
    /// while it is on screen the section stays and shows its checkmarks, so
    /// the layout does not jump on returning from System Settings.
    @State private var showsPermissions: Bool

    init(profiles: [Profile], access: AccessStatus, helper: PrivilegedHelper, viewTier: @escaping (Tier) -> Void) {
        self.profiles = profiles
        self.access = access
        self.helper = helper
        self.viewTier = viewTier
        self.showsPermissions = !access.hasFullDiskAccess || !access.hasAdministratorAccess
    }

    var body: some View {
        Form {
            // Until both permissions are granted some settings read as Unknown
            // or cannot be changed, so setup comes first.
            if showsPermissions {
                PermissionsSection(access: access, helper: helper)
            }
            Section {
                ForEach(profiles) { profile in
                    ProfileRow(profile: profile) {
                        viewTier(profile.tier)
                    } review: {
                        reviewedProfile = profile
                    }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("A profile sets a group of settings to chosen values in one step. Review shows every change before anything is modified.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dashboard")
        .sheet(item: $reviewedProfile) { profile in
            ProfileReviewSheet(profile: profile)
        }
    }
}

struct ProfileRow: View {
    let profile: Profile
    let view: () -> Void
    let review: () -> Void

    var body: some View {
        LabeledContent {
            HStack {
                Button("View", action: view)
                // Only a tier with preset values has anything to review.
                if profile.canApply {
                    Button("Review…", action: review)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                SymbolTile(symbol: profile.symbol, color: profile.tier.color, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.title)
                        .font(.headline)
                    Text(profile.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if profile.canApply {
                        ProfileStatus(
                            total: profile.entries.count,
                            applied: profile.appliedCount,
                            blocked: profile.blockedEntries.count
                        )
                    } else {
                        Text("\(profile.settingCount) settings",
                             comment: "Shown for a tier with no preset values. The variable is the number of settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct ProfileStatus: View {
    let total: Int
    let applied: Int
    let blocked: Int

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(applied), total: Double(max(total, 1)))
                .frame(width: 120)
                .tint(applied == total ? .green : .accentColor)
            Text("\(applied) of \(total) applied",
                 comment: "Profile progress. The first variable is settings already matching, the second is the total.")
            if blocked > 0 {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                    .hoverPopover("\(blocked) cannot be read or changed until Tinker has the permissions listed under Permissions.")
                    .accessibilityLabel("\(blocked) need a permission")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Lists what applying a profile would change, grouped the way the
/// settings are, and applies the checked ones on confirmation.
struct ProfileReviewSheet: View {
    let profile: Profile

    /// Ids of the pending changes that are checked. Starts with all of them.
    @State private var selectedIDs: Set<Profile.Entry.ID>
    @Environment(\.dismiss) private var dismiss

    init(profile: Profile) {
        self.profile = profile
        self.selectedIDs = Set(profile.pendingEntries.map(\.id))
    }

    var body: some View {
        let pending = profile.pendingEntries
        VStack(spacing: 0) {
            Text(profile.title)
                .font(.headline)
                .padding(.top, 16)
            Form {
                if pending.isEmpty {
                    Section {
                        Label("Every setting Tinker can change already matches this profile.", systemImage: "checkmark.circle.fill")
                    }
                }
                ForEach(ProfileChangeGroup.groups(for: pending)) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            SelectableChangeRow(
                                isSelected: $selectedIDs[contains: entry.id],
                                title: entry.item.definition.title,
                                current: entry.item.currentDisplayText,
                                target: entry.item.displayText(for: entry.value)
                            )
                        }
                    }
                }
                BlockedEntriesSection(entries: profile.blockedEntries)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Select All") {
                    selectedIDs = Set(pending.map(\.id))
                }
                .disabled(selectedIDs.count == pending.count)
                Button("Deselect All") {
                    selectedIDs = []
                }
                .disabled(selectedIDs.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Apply Selected") {
                    profile.apply(only: selectedIDs)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 600, height: 560)
    }
}

/// Pending changes that share a "Category: Group" heading.
struct ProfileChangeGroup: Identifiable {
    let title: String
    let entries: [Profile.Entry]

    var id: String { title }

    /// Groups entries by heading, keeping catalog order.
    static func groups(for entries: [Profile.Entry]) -> [ProfileChangeGroup] {
        var order: [String] = []
        var byTitle: [String: [Profile.Entry]] = [:]
        for entry in entries {
            if byTitle[entry.groupTitle] == nil { order.append(entry.groupTitle) }
            byTitle[entry.groupTitle, default: []].append(entry)
        }
        return order.map { ProfileChangeGroup(title: $0, entries: byTitle[$0] ?? []) }
    }
}

struct SelectableChangeRow: View {
    @Binding var isSelected: Bool
    let title: String
    let current: String
    let target: String

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack {
                Text(title)
                Spacer()
                ChangeText(current: current, target: target)
            }
        }
        .toggleStyle(.checkbox)
    }
}

/// Settings in the profile that Tinker cannot change yet, with the reason for each.
struct BlockedEntriesSection: View {
    let entries: [Profile.Entry]

    var body: some View {
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    BlockedEntryRow(
                        title: entry.item.definition.title,
                        groupTitle: entry.groupTitle,
                        reason: entry.item.blocker?.title ?? "Done from the setting's own row"
                    )
                }
            } header: {
                Text("Not Included")
            } footer: {
                Text("These are left as they are. Some need a permission from Tinker's Settings; others open an installer or System Settings and are started from their own row.")
            }
        }
    }
}

struct BlockedEntryRow: View {
    let title: String
    let groupTitle: String
    let reason: LocalizedStringResource

    var body: some View {
        LabeledContent {
            Text(reason)
                .foregroundStyle(.secondary)
        } label: {
            Text(title)
            Text(groupTitle)
        }
    }
}

struct ChangeText: View {
    let current: String
    let target: String

    var body: some View {
        HStack(spacing: 6) {
            Text(current)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("changes to")
            Text(target)
        }
    }
}

extension Set {
    /// Lets a checkbox bind to "is this element in the set".
    subscript(contains element: Element) -> Bool {
        get { contains(element) }
        set {
            if newValue {
                insert(element)
            } else {
                remove(element)
            }
        }
    }
}

extension Tier {
    var color: Color {
        switch self {
        case .recommended: .green
        case .personal: .blue
        case .advanced: .gray
        }
    }
}
