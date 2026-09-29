import SwiftUI

struct CleanupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cleanup = model.cleanup
        VStack(spacing: 0) {
            SectionHeader(section: .cleanup) {
                if cleanup.phase == .results {
                    Button("Scan Again", systemImage: "arrow.clockwise") { cleanup.scan() }
                        .buttonStyle(.glassCapsule)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Group {
                switch cleanup.phase {
                case .idle:
                    ScanIntroView()
                case .scanning:
                    ScanningView()
                case .results:
                    CleanupResultsView()
                case .cleaning:
                    CleaningView()
                case .finished:
                    CleanFinishedView()
                case .failed(let message):
                    FailureView(message: message) { cleanup.scan() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .animation(.smooth(duration: 0.45), value: cleanup.phase)
    }
}

struct FailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(message)
                .caption()
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button("Try Again", action: retry)
                .buttonStyle(.prominentCapsule(.cleanup))
        }
        .foregroundStyle(.white)
        .card(padding: 36)
        .frame(maxWidth: 460)
    }
}
