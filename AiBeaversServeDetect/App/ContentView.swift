import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = ServeDetectionViewModel()

    private let accent = Color(red: 0.0, green: 0.84, blue: 0.58)
    private let warning = Color(red: 1.0, green: 0.49, blue: 0.42)

    @State private var serveFlash = false
    @State private var flashToken = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(
                session: viewModel.captureSession,
                overlayFrame: viewModel.latestOverlayFrame,
                isPreviewMirrored: false
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomControls
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)

            if serveFlash {
                serveBanner
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 72)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: viewModel.serveCount) { newCount in
            guard newCount > 0 else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flashToken += 1
            let token = flashToken
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { serveFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if token == flashToken {
                    withAnimation(.easeOut(duration: 0.4)) { serveFlash = false }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Serve Detect")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer(minLength: 8)
            countPill
        }
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

            Button(action: viewModel.testVoice) {
                Text("Test voice")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var serveBanner: some View {
        Text("Serve \(viewModel.serveCount) detected")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(accent, in: Capsule())
            .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
    }

    private func toggleDetection() {
        if viewModel.isDetecting {
            viewModel.stopDetecting()
        } else {
            viewModel.startDetecting()
        }
    }
}
