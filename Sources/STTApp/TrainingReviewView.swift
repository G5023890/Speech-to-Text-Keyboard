import SwiftUI

struct TrainingReviewView: View {
    let profile: DictationProfile
    let initialTranscript: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var transcript: String

    init(
        profile: DictationProfile,
        initialTranscript: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.profile = profile
        self.initialTranscript = initialTranscript
        self.onSave = onSave
        self.onCancel = onCancel
        _transcript = State(initialValue: initialTranscript)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.bubble")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Training Example")
                        .font(.title3.bold())
                    Text(profile.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            TextEditor(text: $transcript)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button {
                    onSave(transcript)
                } label: {
                    Label("Save Example", systemImage: "tray.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
