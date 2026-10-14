//
//  ContentView.swift
//  Tinker
//

import SwiftUI

extension EnvironmentValues {
    /// Whether setting rows show their preference domain and key.
    @Entry var showsPreferenceKeys = false
}

enum AppSettingsKey {
    static let showsPreferenceKeys = "showsPreferenceKeys"
}

struct ContentView: View {
    let model: AppModel

    var body: some View {
        if let loadError = model.loadError {
            ContentUnavailableView(
                "Could Not Load Settings",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else {
            SettingsBrowser(model: model)
        }
    }
}

/// Sidebar of destinations with the selected one's content beside it.
struct SettingsBrowser: View {
    @Bindable var model: AppModel
    @AppStorage(AppSettingsKey.showsPreferenceKeys) private var showsPreferenceKeys = false

    var body: some View {
        NavigationSplitView {
            SidebarView(sections: model.sidebarSections, selection: $model.selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            DetailView(model: model)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    RestartPill(queue: model.restartQueue)
                }
        }
        .searchable(text: $model.searchText, prompt: "Search")
        .toolbar {
            // The tier filter only narrows a list of settings.
            if model.detailContent == .settingsList {
                ToolbarItem {
                    TierFilterPicker(selection: $model.tierFilter)
                }
            }
        }
        .environment(\.showsPreferenceKeys, showsPreferenceKeys)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadValues()
        }
    }
}

struct DetailView: View {
    let model: AppModel

    var body: some View {
        switch model.detailContent {
        case .dashboard:
            DashboardView(profiles: model.profiles, access: model.access, helper: model.helper, viewTier: model.showAllSettings)
        case .settingsList:
            SettingsDetailView(
                groups: model.visibleGroups,
                title: model.detailTitle,
                isSearching: model.isSearching
            )
        case .appSettings:
            AppSettingsView(access: model.access, helper: model.helper)
        }
    }
}

struct TierFilterPicker: View {
    @Binding var selection: Tier?

    var body: some View {
        Picker("Profile", selection: $selection) {
            Text("All Profiles").tag(Tier?.none)
            Divider()
            ForEach(Tier.allCases) { tier in
                Text(tier.title).tag(Tier?.some(tier))
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Profile")
    }
}
