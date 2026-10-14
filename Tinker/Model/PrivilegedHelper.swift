//
//  PrivilegedHelper.swift
//  Tinker
//

import Foundation
import Observation
import ServiceManagement

/// Something that can make system-wide changes with root rights.
nonisolated protocol PrivilegedPreferenceWriting: Sendable {
    func setSystemValue(_ value: PreferenceValue?, at location: PreferenceLocation) throws
    func perform(_ operation: HelperOperation, argument: String) throws
}

/// Installs, removes and reports on Tinker's root helper, which macOS runs
/// as a launch daemon once the user allows it in System Settings.
@Observable
final class PrivilegedHelper {
    enum Status: Equatable {
        case notInstalled
        /// Registered, waiting for the user to allow it in Login Items & Extensions.
        case needsApproval
        case enabled
    }

    private(set) var status: Status = .notInstalled
    private(set) var errorMessage: String?

    let connection = HelperConnection()

    private let access: AccessStatus
    private let service = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)

    /// Starts as "off"; call `refresh()` to ask macOS for the real state.
    init(access: AccessStatus) {
        self.access = access
    }

    /// Reads the current state from macOS. The user can change it in System
    /// Settings at any time, so call this when the app becomes active.
    func refresh() {
        // macOS reports "not found" for a helper that has never been
        // registered, so that is the same as off. A helper that is really
        // missing surfaces as an error when turning it on.
        status = switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        case .notFound, .notRegistered: .notInstalled
        @unknown default: .notInstalled
        }
        access.hasAdministratorAccess = status == .enabled
    }

    func install() {
        do {
            try service.register()
            errorMessage = nil
        } catch {
            // Registering a daemon that still needs approval reports an
            // error even though the request was recorded; the status says which.
            errorMessage = service.status == .requiresApproval ? nil : error.localizedDescription
        }
        refresh()
    }

    func remove() async {
        do {
            try await service.unregister()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// The app's end of the XPC connection to the helper. Each request opens
/// its own connection and closes it, so the helper can quit between changes.
nonisolated struct HelperConnection: PrivilegedPreferenceWriting {
    func setSystemValue(_ value: PreferenceValue?, at location: PreferenceLocation) throws {
        let wire = PreferenceValue.wireForm(of: value)
        try send { helper, reply in
            helper.setSystemPreference(
                domain: location.domain, key: location.key, kind: wire.kind, payload: wire.payload, reply: reply
            )
        }
    }

    func perform(_ operation: HelperOperation, argument: String) throws {
        try send { helper, reply in
            helper.performOperation(operation.rawValue, argument: argument, reply: reply)
        }
    }

    /// Sends one request and waits for the helper's answer.
    private func send(_ request: (any TinkerHelperProtocol, @escaping (String?) -> Void) -> Void) throws {
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: TinkerHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        let result = ReplyBox()
        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { error in
            result.failure = error.localizedDescription
        }
        guard let helper = proxy as? any TinkerHelperProtocol else {
            throw PreferenceError.helperFailed(String(localized: "Could not reach Tinker's helper."))
        }
        // The proxy is synchronous, so the reply has arrived when this returns.
        request(helper) { failure in
            result.failure = failure
        }
        if let failure = result.failure {
            throw PreferenceError.helperFailed(failure)
        }
    }

    private final class ReplyBox: @unchecked Sendable {
        var failure: String?
    }
}
