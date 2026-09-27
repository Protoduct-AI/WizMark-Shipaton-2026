import Foundation
import Network
import os

// MARK: - NetworkMonitor

/// Observes device connectivity using NWPathMonitor.
/// Provides real-time `isConnected` and `connectionType` for UI and service-layer decisions.
@Observable
final class NetworkMonitor: @unchecked Sendable {

    // MARK: - Published State

    /// Whether the device has any network path in a satisfied state.
    private(set) var isConnected: Bool = true

    /// The primary interface type of the current path (Wi-Fi, cellular, etc.).
    private(set) var connectionType: NWInterface.InterfaceType?

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.protoductai.wizmark.network-monitor", qos: .utility)
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "NetworkMonitor")

    // MARK: - Init

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            let interfaceType = self.resolveInterfaceType(path)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = connected
                self.connectionType = interfaceType
            }

            if connected {
                self.logger.debug("Network connected via \(String(describing: interfaceType), privacy: .public)")
            } else {
                self.logger.info("Network disconnected")
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Private Helpers

    private func resolveInterfaceType(_ path: NWPath) -> NWInterface.InterfaceType? {
        let orderedTypes: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet, .loopback, .other]
        return orderedTypes.first { path.usesInterfaceType($0) }
    }
}
