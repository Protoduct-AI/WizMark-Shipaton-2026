import os
import SwiftUI
import UserNotifications

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case notifications = 0
    case save = 1
    case settings = 2
    case review = 3
    case paywall = 4

    var id: Int { rawValue }
}

@Observable
@MainActor
final class OnboardingViewModel {

    var currentStep: OnboardingStep = .notifications
    private(set) var isComplete: Bool = false
    private(set) var notificationsGranted: Bool = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.protoductai.wizmark",
        category: "Onboarding"
    )

    var totalSteps: Int { OnboardingStep.allCases.count }

    var isTutorialLastStep: Bool { currentStep == .review }

    func advance() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) {
            currentStep = next
        }
    }

    func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            notificationsGranted = granted
            logger.info("Notification permission: \(granted)")
        } catch {
            logger.error("Notification request failed: \(error.localizedDescription)")
        }
        advance()
    }

    func skipNotifications() {
        logger.info("Notification permission skipped")
        advance()
    }

    func showPaywall() {
        advance()
    }

    func completeOnboarding() {
        Storage.set(true, for: .hasCompletedOnboarding)
        logger.info("Onboarding completed")
        withAnimation(.easeInOut(duration: 0.35)) {
            isComplete = true
        }
    }

    static var hasCompletedOnboarding: Bool {
        Storage.bool(for: .hasCompletedOnboarding)
    }
}
