
import AVFoundation
import CoreImage
import CoreVideo
import ImageIO
import Observation
import os

/// A captured camera frame. The pixel buffer is only ever touched on the single task that consumes
/// the frame stream, so it is safe to move across isolation boundaries.
struct CapturedFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
}

/// Manages the camera capture session and exposes the live video frames as an async stream.
@MainActor
@Observable
public final class CameraManager {
    public enum Status: Equatable, Sendable {
        /// The session has not been started yet.
        case uninitialized

        /// The user denied camera access.
        case unauthorized

        /// Access was granted but the session is not yet configured.
        case authorized

        /// An error occurred during setup.
        case error(CameraManagerError)

        /// The session is configured and running.
        case ready
    }

    public enum CameraManagerError: String, Sendable {
        /// The user denied access to the camera.
        case accessDenied

        /// No camera input device is available.
        case noInputDevice
    }

    /// The current status of the camera manager.
    public private(set) var status: Status = .uninitialized

    /// The live stream of camera frames. Only the most recent frame is buffered.
    let frames: AsyncStream<CapturedFrame>

    /// The capture session driving the preview and the frame stream.
    let session = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.nutritionkit.camera.session")
    private let outputQueue = DispatchQueue(label: "com.nutritionkit.camera.output", qos: .userInitiated)

    private let continuation: AsyncStream<CapturedFrame>.Continuation
    private var delegate: FrameCaptureDelegate?
    private var isConfigured = false

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(
            of: CapturedFrame.self, bufferingPolicy: .bufferingNewest(1))

        self.frames = stream
        self.continuation = continuation
    }

    /// Request access, configure the session and start capturing.
    public func start() async {
        guard await Self.requestAuthorization() else {
            self.status = .unauthorized
            return
        }

        self.status = .authorized

        guard self.configureIfNeeded() else {
            self.status = .error(.noInputDevice)
            return
        }

        nonisolated(unsafe) let session = self.session
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }

        self.status = .ready
    }

    /// Stop capturing.
    public func stop() {
        nonisolated(unsafe) let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// Configure the session inputs and outputs once.
    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1920x1080

        guard
            let device = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first,
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            Logger.nutritionKit.error("no camera input device available")
            return false
        }

        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        ]

        let delegate = FrameCaptureDelegate(continuation: continuation, orientation: .right)
        self.delegate = delegate
        videoOutput.setSampleBufferDelegate(delegate, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            Logger.nutritionKit.error("cannot add video output to session")
            return false
        }

        session.addOutput(videoOutput)
        isConfigured = true

        return true
    }

    /// Request camera access, returning whether it was granted.
    private static func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

/// Forwards captured sample buffers into the camera manager's frame stream.
private final class FrameCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let continuation: AsyncStream<CapturedFrame>.Continuation
    let orientation: CGImagePropertyOrientation

    init(continuation: AsyncStream<CapturedFrame>.Continuation, orientation: CGImagePropertyOrientation) {
        self.continuation = continuation
        self.orientation = orientation
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        continuation.yield(CapturedFrame(pixelBuffer: pixelBuffer, orientation: orientation))
    }
}
