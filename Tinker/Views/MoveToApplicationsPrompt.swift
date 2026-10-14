//
//  MoveToApplicationsPrompt.swift
//  Tinker
//

import AppKit

/// Runs before the window opens, so the offer to move comes first.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MoveToApplicationsPrompt.presentIfNeeded()
    }
}

/// Offers to move Tinker into the Applications folder when it is opened
/// from somewhere else, such as Downloads.
enum MoveToApplicationsPrompt {
    private static let suppressionKey = "suppressMoveToApplicationsPrompt"

    /// Development builds run from Xcode's build folder on purpose.
    private static var isEnabled: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    static func presentIfNeeded() {
        let bundleURL = Bundle.main.bundleURL
        guard isEnabled,
              bundleURL.pathExtension == "app",
              !ApplicationsFolder.contains(bundleURL),
              !UserDefaults.standard.bool(forKey: suppressionKey) else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Tinker to the Applications folder?")
        alert.informativeText = String(localized: "Tinker is running from another folder. Its permissions and administrator helper belong to wherever the app lives, so it works best from Applications.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.showsSuppressionButton = true

        NSApp.activate()
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressionKey)
        }
        guard response == .alertFirstButtonReturn else { return }

        do {
            let installedURL = try ApplicationsFolder.install(bundleURL, into: ApplicationsFolder.systemDirectory)
            // A freshly downloaded app runs from a hidden copy, and the file
            // it came from cannot be located, so only a plain copy is trashed.
            if !ApplicationsFolder.isTranslocated(bundleURL) {
                try? FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)
            }
            relaunch(from: installedURL)
        } catch {
            let failure = NSAlert()
            failure.messageText = String(localized: "Tinker could not be moved.")
            failure.informativeText = String(localized: "\(error.localizedDescription) You can drag it into Applications yourself. Tinker will keep running from here for now.")
            failure.runModal()
        }
    }

    /// Opens the installed copy and ends this one before its window appears.
    private static func relaunch(from installedURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", installedURL.path(percentEncoded: false)]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // The app is in Applications either way; carrying on here beats quitting with nothing open.
            return
        }
        exit(EXIT_SUCCESS)
    }
}
