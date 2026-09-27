import Foundation
import LocalAuthentication
import os

// MARK: - BiometricService

/// Provides biometric authentication (Face ID / Touch ID) via the LocalAuthentication framework.
/// Check `isAvailable` before presenting auth prompts.
@Observable
@MainActor
final class BiometricService {

    // MARK: - Published State

    /// The biometric type available on this device (.faceID, .touchID, .opticID, or .none).
    private(set) var biometricType: LABiometryType = .none

    /// Whether biometric authentication is enrolled and available.
    private(set) var isAvailable: Bool = false

    /// Whether an authentication prompt is currently on screen.
    private(set) var isAuthenticating: Bool = false

    // MARK: - Private

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "BiometricService")

    // MARK: - Init

    init() {
        refreshAvailability()
    }

    // MARK: - Public API

    /// Re-evaluate biometric hardware and enrollment.
    /// Call after the user may have changed device settings.
    func refreshAvailability() {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        isAvailable = canEvaluate
        biometricType = context.biometryType

        if let error {
            logger.debug("Biometric check: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Present the system biometric prompt.
    /// - Parameter reason: Localized string explaining why authentication is needed.
    /// - Returns: `true` if the user authenticated successfully.
    func authenticate(reason: String? = nil) async throws -> Bool {
        guard isAvailable else { return false }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = String(localized: "biometric.cancel", defaultValue: "Cancel")
        context.localizedFallbackTitle = String(localized: "biometric.fallback", defaultValue: "Use Passcode")

        let localizedReason = reason ?? String(localized: "biometric.defaultReason", defaultValue: "Authenticate to continue")

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: localizedReason
            )
            return success
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
            logger.debug("Biometric cancelled by user")
            return false
        } catch let error as LAError where error.code == .userFallback {
            logger.debug("User chose fallback authentication")
            return false
        } catch {
            logger.error("Biometric error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Human-readable name for the current biometric type (e.g. "Face ID", "Touch ID").
    var biometricName: String {
        switch biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return String(localized: "biometric.none", defaultValue: "None")
        @unknown default:
            return String(localized: "biometric.unknown", defaultValue: "Biometric")
        }
    }
}
