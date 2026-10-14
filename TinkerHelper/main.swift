//
//  main.swift
//  TinkerHelper
//
//  Runs as root, started on demand by launchd when Tinker connects.
//  It accepts connections only from Tinker, writes only the preference
//  keys in `HelperPolicy`, and quits when Tinker is no longer connected.
//

import Foundation

final class HelperService: NSObject, NSXPCListenerDelegate, TinkerHelperProtocol {
    /// How long to stay running with no connections before quitting.
    private static let idleTimeout: TimeInterval = 15

    // Touched only on the main queue.
    private var connectionCount = 0
    private var pendingExit: DispatchWorkItem?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Messages from any process that is not Tinker, signed by this team, are dropped.
        connection.setCodeSigningRequirement(HelperConstants.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: TinkerHelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.connectionClosed() }
        }
        DispatchQueue.main.async { self.connectionOpened() }
        connection.resume()
        return true
    }

    func setSystemPreference(
        domain: String, key: String, kind: String, payload: String,
        reply: @escaping (String?) -> Void
    ) {
        guard let value = PreferenceValue.fromWireForm(kind: kind, payload: payload) else {
            reply("The helper could not read the value it was sent.")
            return
        }
        if let reason = HelperPolicy.rejection(domain: domain, key: key, value: value) {
            reply(reason)
            return
        }
        CFPreferencesSetValue(
            key as CFString, value?.propertyList, domain as CFString,
            kCFPreferencesAnyUser, kCFPreferencesCurrentHost
        )
        let saved = CFPreferencesSynchronize(domain as CFString, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
        reply(saved ? nil : "The helper could not save \(key) in \(domain).")
    }

    func performOperation(_ operation: String, argument: String, reply: @escaping (String?) -> Void) {
        guard let operation = HelperOperation(rawValue: operation) else {
            reply("Tinker's helper does not know that operation.")
            return
        }
        guard let command = operation.command(argument: argument) else {
            reply("That name is not valid.")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        // Some tools explain a failure on standard output, so keep both.
        let outputPipe = Pipe()
        process.standardError = outputPipe
        process.standardOutput = outputPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            reply("The helper could not start \(command.executable): \(error.localizedDescription)")
            return
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            reply(message.isEmpty ? "\(command.executable) failed with status \(process.terminationStatus)." : message)
            return
        }
        reply(nil)
    }

    func scheduleExitIfIdle() {
        pendingExit?.cancel()
        guard connectionCount == 0 else { return }
        let work = DispatchWorkItem { exit(EXIT_SUCCESS) }
        pendingExit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleTimeout, execute: work)
    }

    private func connectionOpened() {
        connectionCount += 1
        pendingExit?.cancel()
    }

    private func connectionClosed() {
        connectionCount = max(connectionCount - 1, 0)
        scheduleExitIfIdle()
    }
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = service
listener.resume()
// launchd may start the helper for a caller that is then refused; do not linger.
service.scheduleExitIfIdle()
dispatchMain()
