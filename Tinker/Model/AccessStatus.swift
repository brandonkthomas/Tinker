//
//  AccessStatus.swift
//  Tinker
//

import AppKit
import Observation

/// What Tinker is currently allowed to do on this Mac. Setting rows read
/// this, so they unlock as soon as a permission is granted.
@Observable
final class AccessStatus {
    /// The privileged helper is enabled, so `/Library/Preferences` can be written.
    var hasAdministratorAccess = false
    /// Tinker can see inside other apps' containers, where sandboxed apps
    /// such as Safari and TextEdit keep their preferences.
    var hasFullDiskAccess = false
}

nonisolated enum FullDiskAccess {
    /// macOS has no call that answers this, so the check is to open a file
    /// that only apps with Full Disk Access may read. It never shows a prompt.
    static var isGranted: Bool {
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
}
