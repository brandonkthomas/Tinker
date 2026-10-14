//
//  HelperInterface.swift
//  TinkerShared
//
//  Compiled into both the app and the privileged helper, so the two
//  always agree on the service name, the message format and the rules.
//

import Foundation

nonisolated enum HelperConstants {
    /// The launchd label and Mach service the helper listens on.
    static let machServiceName = "net.brandonthomas.Tinker.helper"
    /// File name in the app's `Contents/Library/LaunchDaemons`.
    static let daemonPlistName = "net.brandonthomas.Tinker.helper.plist"
    /// Only code signed as Tinker by this team may talk to the helper.
    static let clientRequirement =
        #"identifier "net.brandonthomas.Tinker" and anchor apple generic and certificate leaf[subject.OU] = "H27DCAP274""#
}

/// The two things the helper does: write or remove a single scalar
/// preference under `/Library/Preferences`, and run one of a fixed set of
/// system commands.
@objc nonisolated protocol TinkerHelperProtocol {
    /// `kind` and `payload` carry the value as text (see `PreferenceValue.wireForm`).
    /// Replies with `nil` on success, or the reason the write was refused.
    func setSystemPreference(
        domain: String, key: String, kind: String, payload: String,
        reply: @escaping (String?) -> Void
    )

    /// `operation` is a `HelperOperation` raw value. Replies with `nil` on
    /// success, or the reason it was refused or failed.
    func performOperation(_ operation: String, argument: String, reply: @escaping (String?) -> Void)
}

/// The system commands the helper will run as root. Each one maps to a
/// fixed program and fixed arguments; the caller chooses only which one,
/// plus a name for the three naming operations. Nothing here runs a shell.
nonisolated enum HelperOperation: String, CaseIterable, Sendable {
    case enableGatekeeper
    /// Since macOS 15 this no longer turns Gatekeeper off. It makes the
    /// "Anywhere" choice appear in Privacy & Security.
    case showGatekeeperAnywhereOption
    case enableFirewall
    case disableFirewall
    case enableRemoteLogin
    case disableRemoteLogin
    case setComputerName
    case setHostName
    case setLocalHostName

    nonisolated struct Command: Equatable, Sendable {
        let executable: String
        let arguments: [String]
    }

    private static let sshDaemon = "/System/Library/LaunchDaemons/ssh.plist"

    /// The exact command for this operation, or `nil` when `argument` is not acceptable.
    func command(argument: String) -> Command? {
        switch self {
        case .enableGatekeeper:
            Command(executable: "/usr/sbin/spctl", arguments: ["--global-enable"])
        case .showGatekeeperAnywhereOption:
            Command(executable: "/usr/sbin/spctl", arguments: ["--global-disable"])
        case .enableFirewall:
            Command(executable: "/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--setglobalstate", "on"])
        case .disableFirewall:
            Command(executable: "/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--setglobalstate", "off"])
        case .enableRemoteLogin:
            Command(executable: "/bin/launchctl", arguments: ["load", "-w", Self.sshDaemon])
        case .disableRemoteLogin:
            Command(executable: "/bin/launchctl", arguments: ["unload", "-w", Self.sshDaemon])
        case .setComputerName:
            Self.isValidComputerName(argument)
                ? Command(executable: "/usr/sbin/scutil", arguments: ["--set", "ComputerName", argument]) : nil
        case .setHostName:
            Self.isValidHostName(argument, allowsDots: true)
                ? Command(executable: "/usr/sbin/scutil", arguments: ["--set", "HostName", argument]) : nil
        case .setLocalHostName:
            Self.isValidHostName(argument, allowsDots: false)
                ? Command(executable: "/usr/sbin/scutil", arguments: ["--set", "LocalHostName", argument]) : nil
        }
    }

    /// The name shown in Sharing settings: any printable text up to 63 characters.
    static func isValidComputerName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 63
            && !name.hasPrefix("-")
            && name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    /// Network names: letters, digits and hyphens, with dots only for a full host name.
    static func isValidHostName(_ name: String, allowsDots: Bool) -> Bool {
        let limit = allowsDots ? 253 : 63
        guard !name.isEmpty, name.count <= limit, !name.hasPrefix("-"), !name.hasPrefix(".") else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || (allowsDots && scalar == "."))
        }
    }
}

/// What the helper agrees to write. This list is compiled into the helper
/// on purpose: it runs as root, so it must not take its rules from a file
/// or from the caller. A unit test keeps it equal to the catalog's
/// system-scope settings.
nonisolated enum HelperPolicy {
    static let allowedKeys: [String: Set<String>] = [
        "com.apple.loginwindow": [
            "GuestEnabled", "LoginwindowText", "AdminHostInfo",
            "HideAdminUsers", "HideLocalUsers", "IncludeNetworkUser", "Kiosk",
        ],
        "com.apple.SoftwareUpdate": [
            "AutomaticDownload", "CriticalUpdateInstall", "ConfigDataInstall",
            "AutomaticallyInstallMacOSUpdates",
        ],
        "com.apple.commerce": ["AutoUpdate"],
    ]

    static let maximumStringLength = 1024

    /// Why a write is not allowed, or `nil` when it is.
    static func rejection(domain: String, key: String, value: PreferenceValue?) -> String? {
        guard allowedKeys[domain]?.contains(key) == true else {
            return "Tinker's helper does not manage \(key) in \(domain)."
        }
        if case .string(let text) = value, text.count > maximumStringLength {
            return "The value is longer than \(maximumStringLength) characters."
        }
        return nil
    }
}

nonisolated extension PreferenceValue {
    /// A text form that crosses the XPC connection without custom classes.
    /// `nil` (remove the key) is sent as kind "delete".
    static func wireForm(of value: PreferenceValue?) -> (kind: String, payload: String) {
        switch value {
        case nil: ("delete", "")
        case .bool(let value): ("bool", value ? "1" : "0")
        case .int(let value): ("int", String(value))
        case .double(let value): ("double", String(value))
        case .string(let value): ("string", value)
        }
    }

    /// Reverses `wireForm`. The outer optional is `nil` when the message is malformed;
    /// the inner optional is `nil` for "remove the key".
    static func fromWireForm(kind: String, payload: String) -> PreferenceValue?? {
        switch kind {
        case "delete": .some(nil)
        case "bool": payload == "1" ? .bool(true) : payload == "0" ? .bool(false) : nil
        case "int": Int(payload).map { .int($0) }
        case "double": Double(payload).map { .double($0) }
        case "string": .string(payload)
        default: nil
        }
    }
}
