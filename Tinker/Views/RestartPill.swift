//
//  RestartPill.swift
//  Tinker
//

import SwiftUI

/// Floats over the bottom of the detail pane after a change that only
/// shows once a process restarts.
struct RestartPill: View {
    let queue: RestartQueue

    var body: some View {
        VStack {
            if !queue.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                    RestartMessage(systemProcesses: queue.systemProcesses, apps: queue.apps)
                    if !queue.systemProcesses.isEmpty {
                        Button("Restart Now", action: queue.restartSystemProcesses)
                    }
                    Button("Dismiss", action: queue.dismiss)
                }
                .controlSize(.small)
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .glassEffect()
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: queue.isEmpty)
    }
}

struct RestartMessage: View {
    let systemProcesses: [String]
    let apps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !systemProcesses.isEmpty {
                Text("Restart \(systemProcesses.formatted(.list(type: .and))) to apply your changes.",
                     comment: "The variable is a list of process names such as Finder and Dock.")
            }
            if !apps.isEmpty {
                Text("Quit and reopen \(apps.formatted(.list(type: .and))) to apply your changes.",
                     comment: "The variable is a list of app names such as Safari and Terminal.")
            }
        }
        .font(.callout)
        .fixedSize()
    }
}
