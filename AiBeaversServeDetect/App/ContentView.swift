import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ServeDetectionViewModel()

    var body: some View {
        ZStack {
            CameraPreview(
                session: viewModel.captureSession,
                overlayFrame: viewModel.latestOverlayFrame,
                isPreviewMirrored: false
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                topPanel
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 22)
        }
        .background(Color.black)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private var topPanel: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Serve Detect")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(viewModel.statusMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(viewModel.serveCount)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(viewModel.serveCount == 1 ? "serve" : "serves")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.49, blue: 0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }

            detectionReadout

            Button(action: toggleDetection) {
                HStack {
                    Spacer()
                    Text(viewModel.isDetecting ? "Stop detecting" : "Start detecting")
                        .font(.system(size: 17, weight: .bold))
                    Spacer()
                }
                .frame(height: 54)
                .background(viewModel.isDetecting ? Color.white : Color(red: 0.0, green: 0.84, blue: 0.58))
                .foregroundStyle(viewModel.isDetecting ? .black : .black)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .disabled(viewModel.isTransitioning)
            .opacity(viewModel.isTransitioning ? 0.65 : 1.0)
        }
        .padding(16)
        .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var detectionReadout: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(viewModel.lastDetectionTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Text(viewModel.lastDetectionDetail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
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
