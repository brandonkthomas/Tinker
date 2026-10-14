//
//  SystemSettings.swift
//  Tinker
//
//  Settings that are not a single preference key: they are read with a
//  system tool and changed with a command, an installer or a pane in
//  System Settings. The catalog names one with `"system": "<name>"`.
//

import AppKit
import SystemConfiguration

nonisolated enum SystemSetting: String, Decodable, CaseIterable, Sendable {
    case gatekeeper
    /// Whether Privacy & Security offers "Anywhere" under "Allow applications from".
    case gatekeeperAnywhereOption
    case firewall
    case remoteLogin
    case fileVault
    case systemIntegrityProtection
    case computerName
    case hostName
    case localHostName
    case homebrew
    case xcodeCommandLineTools
    case finderNewWindowTarget

    /// Changing it runs a command as root through the helper.
    var needsAdministrator: Bool {
        switch self {
        case .gatekeeper, .gatekeeperAnywhereOption, .firewall, .remoteLogin,
             .computerName, .hostName, .localHostName: true
        default: false
        }
    }

    /// Tinker can only report it. SIP is changed from Recovery, not from a running Mac.
    var isReadOnly: Bool { self == .systemIntegrityProtection }

    /// Changing it opens something the user has to finish (System Settings,
    /// an installer), so it is never done as part of applying a profile.
    var isInteractive: Bool {
        switch self {
        case .fileVault, .homebrew, .xcodeCommandLineTools: true
        default: false
        }
    }

    /// Whether "remove the value" means something, as it does for a preference key.
    var supportsReset: Bool { self == .finderNewWindowTarget }

    /// What Tinker reads or runs, shown where preference keys are shown.
    var technicalName: String {
        switch self {
        case .gatekeeper: "spctl  --status"
        case .gatekeeperAnywhereOption: "spctl  --disable-status"
        case .firewall: "socketfilterfw"
        case .remoteLogin: "launchctl  com.openssh.sshd"
        case .fileVault: "fdesetup"
        case .systemIntegrityProtection: "csrutil"
        case .computerName: "scutil  ComputerName"
        case .hostName: "scutil  HostName"
        case .localHostName: "scutil  LocalHostName"
        case .homebrew: "/opt/homebrew/bin/brew"
        case .xcodeCommandLineTools: "xcode-select"
        case .finderNewWindowTarget: "com.apple.finder  NewWindowTarget"
        }
    }
}

/// Where new Finder windows open. Stored by Finder as a four-letter code
/// plus a folder URL; Tinker carries it as one string: a code for the
/// standard folders, or the folder's `file://` URL for any other folder.
nonisolated enum FinderWindowTarget {
    static let home = "PfHm"
    static let desktop = "PfDe"
    static let documents = "PfDo"
    static let otherFolderCode = "PfLo"

    static let standardCodes = [home, desktop, documents]

    /// The folder URL Finder stores beside each standard code.
    static func folderURL(forCode code: String) -> String? {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        switch code {
        case home: return homeURL.absoluteString
        case desktop: return homeURL.appending(path: "Desktop", directoryHint: .isDirectory).absoluteString
        case documents: return homeURL.appending(path: "Documents", directoryHint: .isDirectory).absoluteString
        default: return nil
        }
    }

    /// "Home", "Desktop", "Documents", or the folder's path with `~` for the home folder.
    static func displayName(for value: String) -> String {
        switch value {
        case home: return String(localized: "Home")
        case desktop: return String(localized: "Desktop")
        case documents: return String(localized: "Documents")
        default:
            guard let url = URL(string: value), url.isFileURL else { return value }
            return (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        }
    }
}

nonisolated enum SystemSettingError: LocalizedError {
    case readOnly
    case invalidValue
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .readOnly: String(localized: "This can only be checked here, not changed.")
        case .invalidValue: String(localized: "That value is not valid for this setting.")
        case .commandFailed(let reason): reason
        }
    }
}

/// Reads and changes `SystemSetting`s.
nonisolated protocol SystemSettingsProviding: Sendable {
    /// The current state, or `nil` when it is not set or could not be determined.
    func value(of setting: SystemSetting) -> PreferenceValue?
    func setValue(_ value: PreferenceValue?, for setting: SystemSetting) throws
}

/// The real thing. Reading runs small system tools, so call it off the
/// main thread when reading many at once.
nonisolated struct LiveSystemSettings: SystemSettingsProviding {
    /// Runs the changes that need root. Without one they fail.
    var privilegedWriter: (any PrivilegedPreferenceWriting)?

    private static let finderDomain = "com.apple.finder" as CFString
    private static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    func value(of setting: SystemSetting) -> PreferenceValue? {
        switch setting {
        case .gatekeeper:
            return flag(in: output(of: "/usr/sbin/spctl", "--status"), on: "assessments enabled", off: "assessments disabled")
        case .gatekeeperAnywhereOption:
            guard let report = output(of: "/usr/sbin/spctl", "--disable-status") else { return nil }
            return .bool(report.localizedCaseInsensitiveContains("currently available"))
        case .firewall:
            return flag(in: output(of: "/usr/libexec/ApplicationFirewall/socketfilterfw", "--getglobalstate"), on: "enabled", off: "disabled")
        case .remoteLogin:
            guard let overrides = output(of: "/bin/launchctl", "print-disabled", "system") else { return nil }
            return .bool(!overrides.contains(#""com.openssh.sshd" => disabled"#))
        case .fileVault:
            return flag(in: output(of: "/usr/bin/fdesetup", "status"), on: "FileVault is On", off: "FileVault is Off")
        case .systemIntegrityProtection:
            return flag(in: output(of: "/usr/bin/csrutil", "status"), on: "status: enabled", off: "status: disabled")
        case .computerName:
            return (SCDynamicStoreCopyComputerName(nil, nil) as String?).map(PreferenceValue.string)
        case .localHostName:
            return (SCDynamicStoreCopyLocalHostName(nil) as String?).map(PreferenceValue.string)
        case .hostName:
            // scutil prints "HostName: not set" to stderr and fails when there is none.
            guard let name = output(of: "/usr/sbin/scutil", "--get", "HostName"), !name.isEmpty else { return nil }
            return .string(name)
        case .homebrew:
            return .bool(Self.brewPaths.contains { FileManager.default.isExecutableFile(atPath: $0) })
        case .xcodeCommandLineTools:
            return .bool(output(of: "/usr/bin/xcode-select", "-p") != nil)
        case .finderNewWindowTarget:
            CFPreferencesAppSynchronize(Self.finderDomain)
            guard let code = CFPreferencesCopyAppValue("NewWindowTarget" as CFString, Self.finderDomain) as? String else {
                return nil
            }
            if code == FinderWindowTarget.otherFolderCode,
               let path = CFPreferencesCopyAppValue("NewWindowTargetPath" as CFString, Self.finderDomain) as? String {
                return .string(path)
            }
            return .string(code)
        }
    }

    func setValue(_ value: PreferenceValue?, for setting: SystemSetting) throws {
        switch (setting, value) {
        case (.systemIntegrityProtection, _):
            throw SystemSettingError.readOnly
        case (.gatekeeper, .bool(true)), (.gatekeeperAnywhereOption, .bool(false)):
            // Enabling Gatekeeper also takes the "Anywhere" choice away again.
            try perform(.enableGatekeeper)
        case (.gatekeeperAnywhereOption, .bool(true)):
            do {
                try perform(.showGatekeeperAnywhereOption)
            } catch {
                // spctl ends this step with a failure status even when it
                // worked, because the choice still has to be made in System
                // Settings. The state it leaves behind is what counts.
                guard self.value(of: .gatekeeperAnywhereOption) == .bool(true) else { throw error }
            }
            try open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
        case (.firewall, .bool(let isOn)):
            try perform(isOn ? .enableFirewall : .disableFirewall)
        case (.remoteLogin, .bool(let isOn)):
            try perform(isOn ? .enableRemoteLogin : .disableRemoteLogin)
        case (.computerName, .string(let name)):
            try perform(.setComputerName, argument: name)
        case (.hostName, .string(let name)):
            try perform(.setHostName, argument: name)
        case (.localHostName, .string(let name)):
            try perform(.setLocalHostName, argument: name)
        case (.fileVault, .bool(true)):
            try open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault")
        case (.homebrew, .bool(true)):
            try startHomebrewInstaller()
        case (.xcodeCommandLineTools, .bool(true)):
            // Shows Apple's own install dialog and returns at once.
            _ = output(of: "/usr/bin/xcode-select", "--install")
        case (.finderNewWindowTarget, let value):
            try setFinderWindowTarget(value)
        default:
            throw SystemSettingError.invalidValue
        }
    }

    // MARK: Private

    private func perform(_ operation: HelperOperation, argument: String = "") throws {
        guard operation.command(argument: argument) != nil else { throw SystemSettingError.invalidValue }
        guard let privilegedWriter else { throw PreferenceError.needsAdministrator }
        try privilegedWriter.perform(operation, argument: argument)
    }

    private func open(_ urlString: String) throws {
        guard let url = URL(string: urlString), NSWorkspace.shared.open(url) else {
            throw SystemSettingError.commandFailed(String(localized: "Could not open System Settings."))
        }
    }

    /// Homebrew's installer asks questions and for a password, so it has to
    /// run in Terminal. A `.command` file opens there without Tinker needing
    /// permission to control Terminal.
    private func startHomebrewInstaller() throws {
        let script = """
        #!/bin/bash
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        """
        let file = FileManager.default.temporaryDirectory.appending(path: "Install Homebrew.command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
        } catch {
            throw SystemSettingError.commandFailed(error.localizedDescription)
        }
        guard NSWorkspace.shared.open(file) else {
            throw SystemSettingError.commandFailed(String(localized: "Could not open Terminal to install Homebrew."))
        }
    }

    private func setFinderWindowTarget(_ value: PreferenceValue?) throws {
        let code: String?
        let folder: String?
        switch value {
        case nil:
            (code, folder) = (nil, nil)
        case .string(let text) where FinderWindowTarget.standardCodes.contains(text):
            (code, folder) = (text, FinderWindowTarget.folderURL(forCode: text))
        case .string(let text) where URL(string: text)?.isFileURL == true:
            (code, folder) = (FinderWindowTarget.otherFolderCode, text)
        default:
            throw SystemSettingError.invalidValue
        }
        CFPreferencesSetAppValue("NewWindowTarget" as CFString, code.map { $0 as CFString }, Self.finderDomain)
        CFPreferencesSetAppValue("NewWindowTargetPath" as CFString, folder.map { $0 as CFString }, Self.finderDomain)
        guard CFPreferencesAppSynchronize(Self.finderDomain) else {
            throw PreferenceError.writeFailed(domain: "com.apple.finder", key: "NewWindowTarget")
        }
    }

    private func flag(in text: String?, on: String, off: String) -> PreferenceValue? {
        guard let text else { return nil }
        if text.localizedCaseInsensitiveContains(on) { return .bool(true) }
        if text.localizedCaseInsensitiveContains(off) { return .bool(false) }
        return nil
    }

    /// Standard output of a tool, or `nil` when it could not run or reported failure.
    private func output(of executable: String, _ arguments: String...) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
