import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.setDevice(device)
    }

    final class PreviewView: UIView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("Use init(frame:) instead")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            // SwiftUI supplies each animated container size. Keep the video and
            // its aspect-fill crop in step, without a second layer animation.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            previewLayer.layoutIfNeeded()
            CATransaction.commit()
        }

        func setDevice(_ device: AVCaptureDevice?) {
            guard let device, rotationCoordinator?.device !== device else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                // RotationCoordinator explicitly delivers preview updates on the main queue.
                MainActor.assumeIsolated {
                    guard let connection = self?.previewLayer.connection else { return }
                    let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                }
            }
        }
    }
}
