//
//  RestartQueue.swift
//  Tinker
//

import Foundation
import Observation

/// Collects the processes that must restart before recent changes show.
@Observable
final class RestartQueue {
    /// Background processes macOS relaunches on its own, safe to restart for the user.
    private(set) var systemProcesses: [String] = []
    /// Regular apps. Restarting these could lose work, so the user reopens them.
    private(set) var apps: [String] = []

    private static let relaunchedBySystem: Set<String> = [
        "Dock", "Finder", "SystemUIServer", "ControlCenter", "WindowManager",
    ]

    var isEmpty: Bool { systemProcesses.isEmpty && apps.isEmpty }

    func add(_ names: [String]) {
        for name in names {
            if Self.relaunchedBySystem.contains(name) {
                if !systemProcesses.contains(name) { systemProcesses.append(name) }
            } else if !apps.contains(name) {
                apps.append(name)
            }
        }
    }

    func restartSystemProcesses() {
        for name in systemProcesses {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/killall")
            process.arguments = [name]
            // killall exits non-zero when the process is not running, which is fine.
            try? process.run()
        }
        systemProcesses = []
    }

    func dismiss() {
        systemProcesses = []
        apps = []
    }
}
