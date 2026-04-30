import Combine
import Foundation

enum AppPhase: Equatable {
    case idle
    case recording(DictationProfile)
    case transcribing(DictationProfile)
    case error(String)

    var isReadyForRecording: Bool {
        if case .idle = self { return true }
        if case .error = self { return true }
        return false
    }
}

enum MicrophonePermission: String {
    case unknown = "Unknown"
    case granted = "Granted"
    case denied = "Denied"
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .idle
    @Published var statusMessage = "Ready"
    @Published var microphonePermission: MicrophonePermission = .unknown
    @Published var accessibilityTrusted = false
    @Published var activeProfile: DictationProfile = .mixedRuEn
    @Published var useVAD = false
    @Published var modelManager: ModelManager?

    var cancellables = Set<AnyCancellable>()

    func refreshPermissions() {
        microphonePermission = PermissionService.microphonePermission()
        accessibilityTrusted = PermissionService.isAccessibilityTrusted(prompt: false)
    }
}
