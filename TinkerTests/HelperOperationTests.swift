//
//  HelperOperationTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// Which commands the root helper agrees to run.
struct HelperOperationTests {
    /// Every operation is one fixed program; only the three naming ones take text, and only valid names.
    @Test func operationsMapToFixedCommands() {
        #expect(HelperOperation.enableFirewall.command(argument: "ignored")
            == .init(executable: "/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--setglobalstate", "on"]))
        #expect(HelperOperation.disableRemoteLogin.command(argument: "")
            == .init(executable: "/bin/launchctl", arguments: ["unload", "-w", "/System/Library/LaunchDaemons/ssh.plist"]))
        #expect(HelperOperation.setLocalHostName.command(argument: "studio")
            == .init(executable: "/usr/sbin/scutil", arguments: ["--set", "LocalHostName", "studio"]))
        for operation in HelperOperation.allCases {
            let command = operation.command(argument: "valid-name")
            #expect(command?.executable.hasPrefix("/") == true)
            #expect(!["/bin/sh", "/bin/bash", "/bin/zsh"].contains(command?.executable))
        }
    }

    @Test func namesAreValidatedBeforeAnythingRuns() {
        #expect(HelperOperation.setComputerName.command(argument: "Sam's MacBook Pro") != nil)
        #expect(HelperOperation.setComputerName.command(argument: "") == nil)
        #expect(HelperOperation.setComputerName.command(argument: "bad\nname") == nil)
        #expect(HelperOperation.setComputerName.command(argument: String(repeating: "x", count: 64)) == nil)
        #expect(HelperOperation.setLocalHostName.command(argument: "my mac") == nil)
        #expect(HelperOperation.setLocalHostName.command(argument: "my.mac") == nil)
        #expect(HelperOperation.setLocalHostName.command(argument: "-flag") == nil)
        #expect(HelperOperation.setHostName.command(argument: "studio.local") != nil)
        #expect(HelperOperation.setHostName.command(argument: "studio; rm -rf /") == nil)
    }
}
