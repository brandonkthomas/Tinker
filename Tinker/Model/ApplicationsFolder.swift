//
//  ApplicationsFolder.swift
//  Tinker
//

import Foundation

/// Working out whether Tinker runs from an Applications folder, and
/// installing it into one.
nonisolated enum ApplicationsFolder {
    static let systemDirectory = URL(fileURLWithPath: "/Applications", isDirectory: true)

    /// True for `/Applications`, `~/Applications`, and any folder inside them.
    static func contains(_ bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.deletingLastPathComponent().pathComponents.contains("Applications")
    }

    /// macOS runs a freshly downloaded app from a hidden read-only copy
    /// until it has been moved in Finder. The copy can be read but the
    /// original it came from cannot be found.
    static func isTranslocated(_ bundleURL: URL) -> Bool {
        bundleURL.pathComponents.contains("AppTranslocation")
    }

    /// Copies the app into `directory` and returns where it now lives.
    /// An app of the same name already there goes to the Trash first.
    static func install(_ bundleURL: URL, into directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let destination = directory.appending(path: bundleURL.lastPathComponent, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: bundleURL, to: destination)
        removeQuarantine(from: destination)
        return destination
    }

    /// The copy keeps the "downloaded from the internet" mark of the
    /// original, which would make macOS run it from a hidden location again.
    /// The user has already agreed to open this app, so the mark is dropped.
    private static func removeQuarantine(from bundleURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", bundleURL.path(percentEncoded: false)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
