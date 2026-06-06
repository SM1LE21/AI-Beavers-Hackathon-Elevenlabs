import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ServeDetectionViewModel()

    private let accent = Color(red: 0.0, green: 0.84, blue: 0.58)
    private let warning = Color(red: 1.0, green: 0.49, blue: 0.42)

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(
                session: viewModel.captureSession,
                overlayFrame: viewModel.latestOverlayFrame,
                isPreviewMirrored: false
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.isDetecting {
                    HStack {
                        Spacer()
                        countPill
                    }
                }
                Spacer(minLength: 0)
                bottomControls
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private var countPill: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(viewModel.serveCount)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(viewModel.serveCount == 1 ? "serve" : "serves")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(accent.opacity(0.55), lineWidth: 1))
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: toggleDetection) {
                Text(viewModel.isDetecting ? "Stop" : "Start detecting")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(viewModel.isDetecting ? Color.white.opacity(0.95) : accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(viewModel.isTransitioning)
            .opacity(viewModel.isTransitioning ? 0.6 : 1.0)
        }
    }

    private func toggleDetection() {
        if viewModel.isDetecting {
            viewModel.stopDetecting()
        } else {
            viewModel.startDetecting()
        }
    }
}
