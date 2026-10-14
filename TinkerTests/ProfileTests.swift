//
//  ProfileTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// Building profiles from tiers and applying them.
@MainActor
struct ProfileTests {
    let store = InMemoryPreferenceStore()

    @Test func profilesComeFromTiersWithProfileValues() throws {
        let model = try makeSampleModel(store: store)
        #expect(model.profiles.map(\.tier) == [.recommended, .personal, .advanced])
        #expect(model.profiles.map(\.canApply) == [true, true, false])
        #expect(model.profiles.map(\.settingCount) == [3, 1, 1])
        #expect(model.profiles.first?.entries.map(\.id) == ["finder.hidden", "finder.warning", "finder.guest"])
    }

    @Test func applyingAProfileWritesOnlyWhatDiffersAndCanBeChanged() throws {
        let model = try makeSampleModel(store: store)
        let profile = try #require(model.profiles.first)
        // Guest account is already off by default, so it counts as applied.
        #expect(profile.appliedCount == 1)
        #expect(profile.pendingEntries.map(\.id) == ["finder.hidden", "finder.warning"])
        #expect(profile.blockedEntries.isEmpty)

        profile.apply()
        #expect(store.values[PreferenceLocation(domain: "com.apple.finder", key: "AppleShowAllFiles")] == .bool(true))
        #expect(store.values[PreferenceLocation(domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning")] == .bool(false))
        #expect(profile.appliedCount == 3)
        #expect(profile.pendingEntries.isEmpty)
    }

    @Test func onlySelectedChangesAreApplied() throws {
        let model = try makeSampleModel(store: store)
        let profile = try #require(model.profiles.first)
        profile.apply(only: ["finder.warning"])
        #expect(store.values[PreferenceLocation(domain: "com.apple.finder", key: "AppleShowAllFiles")] == nil)
        #expect(store.values[PreferenceLocation(domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning")] == .bool(false))
        #expect(profile.pendingEntries.map(\.id) == ["finder.hidden"])
    }

    @Test func reviewGroupsChangesUnderCategoryAndGroup() throws {
        let model = try makeSampleModel(store: store)
        let personal = try #require(model.profiles.first { $0.tier == .personal })
        #expect(personal.entries.map(\.groupTitle) == ["Dock: Behavior"])
        let recommended = try #require(model.profiles.first)
        let groups = ProfileChangeGroup.groups(for: recommended.pendingEntries)
        #expect(groups.map(\.title) == ["Finder: Visibility"])
        #expect(groups.first?.entries.count == 2)
    }

    @Test func settingsNeedingAdministratorAreReportedNotApplied() throws {
        let guest = PreferenceLocation(domain: "com.apple.loginwindow", key: "GuestEnabled", scope: .system)
        store.values[guest] = .bool(true)
        let model = try makeSampleModel(store: store)
        let profile = try #require(model.profiles.first)
        #expect(profile.blockedEntries.map(\.id) == ["finder.guest"])

        profile.apply()
        #expect(store.values[guest] == .bool(true))

        // With administrator access the same entry becomes an ordinary pending change.
        store.allowsSystemWrites = true
        model.access.hasAdministratorAccess = true
        #expect(profile.blockedEntries.isEmpty)
        profile.apply()
        #expect(store.values[guest] == .bool(false))
    }
}
