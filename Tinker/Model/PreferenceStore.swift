//
//  PreferenceStore.swift
//  Tinker
//

import Foundation

/// Where one preference key lives.
nonisolated struct PreferenceLocation: Hashable, Sendable {
    enum Host: String, Decodable, Sendable {
        /// Applies on every Mac the user signs in to (`defaults write`).
        case any
        /// Applies on this Mac only (`defaults -currentHost write`).
        case current
    }

    enum Scope: String, Decodable, Sendable {
        /// `~/Library/Preferences`.
        case user
        /// `/Library/Preferences`. Writing needs administrator access.
        case system
    }

    /// A bundle identifier, or `NSGlobalDomain`.
    var domain: String
    var key: String
    var host: Host = .any
    var scope: Scope = .user
    /// True for a sandboxed app, which keeps its preferences inside its
    /// container instead of in `~/Library/Preferences`.
    var isInAppContainer = false
}

nonisolated enum PreferenceError: LocalizedError {
    case needsAdministrator
    case writeFailed(domain: String, key: String)
    /// The privileged helper refused the write or could not be reached.
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .needsAdministrator:
            String(localized: "This setting needs administrator access. Turn it on in Tinker's Settings.")
        case .writeFailed(let domain, let key):
            String(localized: "Could not write \(key) in \(domain).")
        case .helperFailed(let reason):
            reason
        }
    }
}

/// Reads and writes scalar preference values.
nonisolated protocol PreferenceStore: Sendable {
    /// The value stored at `location`, or `nil` when the key is absent.
    func value(at location: PreferenceLocation) -> PreferenceValue?

    /// Stores `value` at `location`. Passing `nil` removes the key, which
    /// returns the setting to the system default.
    func setValue(_ value: PreferenceValue?, at location: PreferenceLocation) throws
}

/// The real preferences system, through `CFPreferences`.
nonisolated struct SystemPreferenceStore: PreferenceStore {
    /// Writes system-wide preferences as root. Without one, they are read-only.
    var privilegedWriter: (any PrivilegedPreferenceWriting)?

    func value(at location: PreferenceLocation) -> PreferenceValue? {
        let target = Target(location)
        // Other processes (System Settings, `defaults`) may have changed the
        // value since this process last read it.
        CFPreferencesSynchronize(target.application, target.user, target.host)
        guard let raw = CFPreferencesCopyValue(
            location.key as CFString, target.application, target.user, target.host
        ) else { return nil }
        return PreferenceValue(propertyList: raw)
    }

    func setValue(_ value: PreferenceValue?, at location: PreferenceLocation) throws {
        guard location.scope == .user else {
            guard let privilegedWriter else { throw PreferenceError.needsAdministrator }
            try privilegedWriter.setSystemValue(value, at: location)
            return
        }
        let target = Target(location)
        CFPreferencesSetValue(
            location.key as CFString, value?.propertyList, target.application, target.user, target.host
        )
        guard CFPreferencesSynchronize(target.application, target.user, target.host) else {
            throw PreferenceError.writeFailed(domain: location.domain, key: location.key)
        }
    }

    private struct Target {
        let application: CFString
        let user: CFString
        let host: CFString

        init(_ location: PreferenceLocation) {
            application = location.domain == "NSGlobalDomain"
                ? kCFPreferencesAnyApplication
                : SystemPreferenceStore.applicationIdentifier(for: location) as CFString
            switch location.scope {
            case .user:
                user = kCFPreferencesCurrentUser
                host = location.host == .current ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
            case .system:
                user = kCFPreferencesAnyUser
                host = kCFPreferencesCurrentHost
            }
        }

    }

    /// What `CFPreferences` is asked for. A sandboxed app (Safari, TextEdit)
    /// keeps its preferences inside its container, and a bundle identifier
    /// alone reaches the wrong file from an unsandboxed app, so those are
    /// named by the container file's path, which is what `defaults` does too.
    ///
    /// Only locations the catalog marks as containerized are redirected. Many
    /// other apps have a container folder without keeping preferences in it,
    /// and reaching into one makes macOS ask for access to that app's data.
    static func applicationIdentifier(for location: PreferenceLocation) -> String {
        guard location.isInAppContainer, location.scope == .user else { return location.domain }
        let container = NSHomeDirectory() + "/Library/Containers/\(location.domain)"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: container, isDirectory: &isDirectory),
              isDirectory.boolValue else { return location.domain }
        return container + "/Data/Library/Preferences/\(location.domain)"
    }
}
