import AppIntents
import AppKit
import SwiftUI
import WidgetKit

public struct VoiceInputStatusControl: ControlWidget {
    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: VoiceInputShared.controlKind,
            provider: Provider()
        ) { isRunning in
            ControlWidgetButton(action: OpenURLIntent(VoiceInputShared.controlOpenURL)) {
                Label(
                    isRunning ? "Running" : "Not Running",
                    systemImage: isRunning ? "waveform.circle.fill" : "waveform.circle"
                )
            }
            .tint(isRunning ? .green : .secondary)
        }
        .displayName("Voice Input")
        .description("Shows whether Voice Input is running and opens the app.")
    }
}

extension VoiceInputStatusControl {
    public struct Provider: ControlValueProvider {
        public init() {}

        public var previewValue: Bool { false }

        public func currentValue() async throws -> Bool {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: VoiceInputShared.appBundleIdentifier)
                .contains(where: { !$0.isTerminated })
        }
    }
}
