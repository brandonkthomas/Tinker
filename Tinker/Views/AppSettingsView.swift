//
//  AppSettingsView.swift
//  Tinker
//

import SwiftUI

/// Tinker's own options, as opposed to the macOS settings it edits.
struct AppSettingsView: View {
    let access: AccessStatus
    let helper: PrivilegedHelper

    @AppStorage(AppSettingsKey.showsPreferenceKeys) private var showsPreferenceKeys = false

    var body: some View {
        Form {
            Section("Display") {
                Toggle(isOn: $showsPreferenceKeys) {
                    HStack(spacing: 6) {
                        Text("Show preference keys")
                        InfoButton(text: Text("Shows the preference domain and key under each setting, for example com.apple.dock autohide."))
                    }
                }
            }
            PermissionsSection(access: access, helper: helper)
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

/// The two permissions Tinker needs to read and change every setting.
struct PermissionsSection: View {
    let access: AccessStatus
    let helper: PrivilegedHelper

    var body: some View {
        Section {
            FullDiskAccessRow(isGranted: access.hasFullDiskAccess)
            AdminAccessRow(helper: helper)
            if let errorMessage = helper.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Permissions")
        }
    }
}

struct FullDiskAccessRow: View {
    let isGranted: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        LabeledContent {
            Button("Open Privacy Settings…") {
                if let url = FullDiskAccess.settingsURL { openURL(url) }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Full Disk Access")
                InfoButton(text: Text("Safari and TextEdit keep their settings in a protected folder. Without Full Disk Access Tinker cannot read them, so it shows them as Unknown."))
            }
            PermissionStatusText(
                title: isGranted ? "On" : "Off. Safari and TextEdit settings show as Unknown",
                symbol: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                color: isGranted ? .green : .orange
            )
        }
    }
}

/// Turns Tinker's root helper on and off and shows where it stands.
struct AdminAccessRow: View {
    let helper: PrivilegedHelper

    var body: some View {
        LabeledContent {
            AdminAccessButtons(helper: helper)
        } label: {
            HStack(spacing: 6) {
                Text("Administrator access")
                InfoButton(text: Text("Some settings are stored for the whole Mac and can only be changed as an administrator. Tinker uses a small helper that macOS runs in the background only while a change is being made. It can change only the settings listed in Tinker."))
            }
            AdminAccessStatusText(status: helper.status)
        }
    }
}

struct PermissionStatusText: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct AdminAccessStatusText: View {
    let status: PrivilegedHelper.Status

    var body: some View {
        PermissionStatusText(title: title, symbol: symbol, color: color)
    }

    private var title: LocalizedStringKey {
        switch status {
        case .notInstalled: "Off. System-wide settings are read-only"
        case .needsApproval: "Waiting for you to allow Tinker in System Settings"
        case .enabled: "On"
        }
    }

    private var symbol: String {
        switch status {
        case .notInstalled, .needsApproval: "exclamationmark.circle.fill"
        case .enabled: "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .notInstalled, .needsApproval: .orange
        case .enabled: .green
        }
    }
}

struct AdminAccessButtons: View {
    let helper: PrivilegedHelper

    var body: some View {
        HStack {
            switch helper.status {
            case .notInstalled:
                Button("Turn On", action: helper.install)
            case .needsApproval:
                Button("Open Login Items…", action: helper.openLoginItemsSettings)
                Button("Cancel") {
                    Task { await helper.remove() }
                }
            case .enabled:
                Button("Turn Off") {
                    Task { await helper.remove() }
                }
            }
        }
    }
}
