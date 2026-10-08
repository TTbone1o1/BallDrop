@preconcurrency import AVFoundation
import Combine
import Observation

@MainActor
@Observable
final class CameraManager {
    enum Status {
        case idle, requestingPermission, starting, running
        case denied, restricted, unavailable, interrupted, failed
    }

    private(set) var status: Status = .idle
    private(set) var device: AVCaptureDevice?

    // Only the preview layer uses this reference on the main thread. All session
    // configuration and start/stop work is confined to CaptureSession's executor.
    var session: AVCaptureSession { capture.session }

    private let capture = CaptureSession()
    private var wantsToRun = false
    private var operation: Task<Void, Never>?
    private var observations: [AnyCancellable] = []

    init() {
        observeSession()
    }

    func setActive(_ active: Bool) {
        guard wantsToRun != active else { return }
        wantsToRun = active
        enqueueSessionUpdate()
    }

    private func enqueueSessionUpdate() {
        let previousOperation = operation
        previousOperation?.cancel()
        // Serialize lifecycle changes too, so a late permission response or an
        // in-flight start cannot leave the camera running after backgrounding.
        operation = Task { [weak self] in
            await previousOperation?.value
            guard !Task.isCancelled, let self else { return }
            if wantsToRun {
                await start()
            } else {
                await capture.stop()
            }
        }
    }

    private func start() async {
        var authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if authorization == .notDetermined {
            status = .requestingPermission
            _ = await AVCaptureDevice.requestAccess(for: .video)
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }

        guard !Task.isCancelled, wantsToRun else { return }
        switch authorization {
        case .authorized:
            status = .starting
            do {
                let camera = try await capture.start()
                let interrupted = await capture.isInterrupted
                guard !Task.isCancelled, wantsToRun else { return }
                device = camera
                status = interrupted ? .interrupted : .running
            } catch CaptureSession.Failure.noCamera {
                guard !Task.isCancelled, wantsToRun else { return }
                status = .unavailable
            } catch {
                guard !Task.isCancelled, wantsToRun else { return }
                status = .failed
            }
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        case .notDetermined:
            status = .idle
        @unknown default:
            status = .unavailable
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        center.publisher(for: AVCaptureSession.wasInterruptedNotification, object: session)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, wantsToRun else { return }
                status = .interrupted
            }
            .store(in: &observations)

        center.publisher(for: AVCaptureSession.interruptionEndedNotification, object: session)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, wantsToRun else { return }
                enqueueSessionUpdate()
            }
            .store(in: &observations)

        center.publisher(for: AVCaptureSession.runtimeErrorNotification, object: session)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, wantsToRun else { return }
                if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError,
                   error.code == .mediaServicesWereReset {
                    enqueueSessionUpdate()
                } else {
                    status = .failed
                }
            }
            .store(in: &observations)
    }
}

// A small, private worker keeps AVFoundation's blocking calls off the main actor.
private actor CaptureSession {
    enum Failure: Error {
        case noCamera, cannotAddInput, cannotStart
    }

    private let queue = DispatchSerialQueue(label: "com.balldrop.camera", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    nonisolated let session = AVCaptureSession()
    private var camera: AVCaptureDevice?

    var isInterrupted: Bool { session.isInterrupted }

    func start() throws -> AVCaptureDevice {
        if camera == nil {
            try configure()
        }
        guard let camera else { throw Failure.noCamera }
        if !session.isRunning {
            session.startRunning()
        }
        guard session.isRunning || session.isInterrupted else { throw Failure.cannotStart }
        return camera
    }

    func stop() {
        // Also cancels a pending run request when the session is interrupted.
        session.stopRunning()
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw Failure.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input) else { throw Failure.cannotAddInput }
        session.addInput(input)
        camera = device
        // No outputs: this milestone previews video without capturing media.
    }
}
