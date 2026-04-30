import ApplicationServices
import AVFoundation
import Foundation

enum PermissionService {
    static func microphonePermission() -> MicrophonePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    static func requestMicrophoneAccess() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestAccessibilityAccess() {
        _ = isAccessibilityTrusted(prompt: true)
    }
}
