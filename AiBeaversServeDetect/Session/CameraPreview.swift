import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let overlayFrame: LiveOverlayFrame?
    let isPreviewMirrored: Bool

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.update(
            session: session,
            overlayFrame: overlayFrame,
            isPreviewMirrored: isPreviewMirrored
        )
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.update(
            session: session,
            overlayFrame: overlayFrame,
            isPreviewMirrored: isPreviewMirrored
        )
    }
}

final class CameraPreviewView: UIView {
    private let skeletonLayer = CAShapeLayer()
    private let jointsLayer = CAShapeLayer()
    private var currentOverlayFrame: LiveOverlayFrame?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill

        skeletonLayer.fillColor = UIColor.clear.cgColor
        skeletonLayer.strokeColor = UIColor(red: 0.0, green: 0.95, blue: 0.66, alpha: 1).cgColor
        skeletonLayer.lineWidth = 3
        skeletonLayer.lineCap = .round
        skeletonLayer.lineJoin = .round

        jointsLayer.fillColor = UIColor.white.cgColor
        jointsLayer.strokeColor = UIColor.black.withAlphaComponent(0.35).cgColor
        jointsLayer.lineWidth = 1

        previewLayer.addSublayer(skeletonLayer)
        previewLayer.addSublayer(jointsLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        skeletonLayer.frame = bounds
        jointsLayer.frame = bounds
        redrawOverlay()
    }

    func update(
        session: AVCaptureSession,
        overlayFrame: LiveOverlayFrame?,
        isPreviewMirrored: Bool
    ) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }

        if let connection = previewLayer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = isPreviewMirrored
            }
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        currentOverlayFrame = overlayFrame
        redrawOverlay()
    }

    private func redrawOverlay() {
        guard let overlayFrame = currentOverlayFrame else {
            skeletonLayer.path = nil
            jointsLayer.path = nil
            return
        }

        let bodyFrame = overlayFrame.bodyFrame
        let skeletonPath = UIBezierPath()
        let jointPath = UIBezierPath()

        for connection in bodyConnections {
            guard
                let start = layerPoint(for: bodyFrame.point(connection.0)),
                let end = layerPoint(for: bodyFrame.point(connection.1))
            else {
                continue
            }
            skeletonPath.move(to: start)
            skeletonPath.addLine(to: end)
        }

        for landmarkName in LandmarkName.analysisCases {
            guard let point = layerPoint(for: bodyFrame.point(landmarkName)) else {
                continue
            }
            let radius: CGFloat = isMajorJoint(landmarkName) ? 4.8 : 3.6
            jointPath.append(UIBezierPath(ovalIn: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )))
        }

        skeletonLayer.path = skeletonPath.cgPath
        jointsLayer.path = jointPath.cgPath
    }

    private func layerPoint(for normalizedPoint: CGPoint?) -> CGPoint? {
        guard let normalizedPoint else {
            return nil
        }
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
    }

    private func isMajorJoint(_ landmarkName: LandmarkName) -> Bool {
        switch landmarkName {
        case .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftWrist, .rightWrist:
            return true
        default:
            return false
        }
    }

    private let bodyConnections: [(LandmarkName, LandmarkName)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
    ]
}
