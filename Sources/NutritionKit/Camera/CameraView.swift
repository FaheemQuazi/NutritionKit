
import AVFoundation
import CoreImage
import SwiftUI
import Vision

// MARK: - Preview

/// A SwiftUI wrapper around `AVCaptureVideoPreviewLayer`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - Container

/// Displays the live camera feed (once ready) with an overlay, handling the loading/error states.
struct AnyCameraView<Overlay: View>: View {
    /// The camera manager driving the feed.
    let camera: CameraManager

    /// The overlay shown above the feed.
    let overlay: Overlay

    init(camera: CameraManager, @ViewBuilder overlay: () -> Overlay) {
        self.camera = camera
        self.overlay = overlay()
    }

    private func errorView(_ error: CameraManager.CameraManagerError) -> some View {
        ZStack {
            Rectangle().fill(Color.black)
            Text(verbatim: error.rawValue)
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    var body: some View {
        ZStack {
            switch camera.status {
            case .ready:
                CameraPreview(session: camera.session)
                    .overlay { overlay }
            case .error(let error):
                errorView(error)
            case .uninitialized, .unauthorized, .authorized:
                Rectangle().fill(Color.black)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Vision helpers

/// Converts camera pixel buffers into images for Vision processing.
enum CameraImage {
    // CIContext is thread-safe; sharing one avoids per-frame allocation.
    static let ciContext = CIContext()

    static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}

/// Detects barcodes in camera frames using the Vision barcode request.
enum BarcodeDetector {
    /// Symbologies commonly found on packaged food products.
    static let symbologies: [BarcodeSymbology] = [
        .ean13, .ean8, .upce, .code128, .code39, .code93, .qr, .pdf417, .dataMatrix, .aztec,
    ]

    static func detect(in frame: CapturedFrame) async -> Barcode? {
        var request = DetectBarcodesRequest()
        request.symbologies = symbologies

        guard let results = try? await request.perform(on: frame.pixelBuffer, orientation: frame.orientation) else {
            return nil
        }

        guard let observation = results.first(where: { ($0.payloadString?.isEmpty == false) }),
              let data = observation.payloadString else {
            return nil
        }

        let corners = [observation.topLeft, observation.topRight, observation.bottomLeft, observation.bottomRight]
            .map { CGPoint(x: $0.x, y: $0.y) }

        return Barcode(data: data, corners: corners)
    }
}

// MARK: - Cutout overlay shapes

public struct CameraCutoutShape: Shape, Animatable {
    var points: CameraRect

    public var animatableData: CameraRect {
        get { points }
        set { points = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        path.addRect(rect)
        path.closeSubpath()

        let topLeft = points.first
        let topRight = points.second
        let bottomLeft = points.third
        let bottomRight = points.fourth

        path.move(to: .init(x: topLeft.x * rect.width, y: rect.height - topLeft.y * rect.height))
        path.addLine(to: .init(x: topRight.x * rect.width, y: rect.height - topRight.y * rect.height))
        path.addLine(to: .init(x: bottomRight.x * rect.width, y: rect.height - bottomRight.y * rect.height))
        path.addLine(to: .init(x: bottomLeft.x * rect.width, y: rect.height - bottomLeft.y * rect.height))
        path.addLine(to: .init(x: topLeft.x * rect.width, y: rect.height - topLeft.y * rect.height))

        path.closeSubpath()

        return path
    }
}

public struct CameraCutoutStrokeShape: Shape, Animatable {
    let lineLength: CGFloat
    var points: CameraRect

    public var animatableData: CameraRect {
        get { points }
        set { points = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        let topLeft = CGPoint(x: points.first.x * rect.width, y: rect.height - points.first.y * rect.height)
        let topRight = CGPoint(x: points.second.x * rect.width, y: rect.height - points.second.y * rect.height)
        let bottomLeft = CGPoint(x: points.third.x * rect.width, y: rect.height - points.third.y * rect.height)
        let bottomRight = CGPoint(x: points.fourth.x * rect.width, y: rect.height - points.fourth.y * rect.height)

        // Top Left
        path.move(to: topLeft)
        path.addLine(to: topLeft + (topRight - topLeft).normalized * lineLength)
        path.move(to: topLeft)
        path.addLine(to: topLeft + (bottomLeft - topLeft).normalized * lineLength)

        // Top Right
        path.move(to: topRight)
        path.addLine(to: topRight + (topLeft - topRight).normalized * lineLength)
        path.move(to: topRight)
        path.addLine(to: topRight + (bottomRight - topRight).normalized * lineLength)

        // Bottom Left
        path.move(to: bottomLeft)
        path.addLine(to: bottomLeft + (topLeft - bottomLeft).normalized * lineLength)
        path.move(to: bottomLeft)
        path.addLine(to: bottomLeft + (bottomRight - bottomLeft).normalized * lineLength)

        // Bottom Right
        path.move(to: bottomRight)
        path.addLine(to: bottomRight + (topRight - bottomRight).normalized * lineLength)
        path.move(to: bottomRight)
        path.addLine(to: bottomRight + (bottomLeft - bottomRight).normalized * lineLength)

        return path
    }
}

public struct DefaultCameraOverlayView: View {
    /// The current corner points.
    @Binding var rectangle: CameraRect

    public init(rectangle: Binding<CameraRect>) {
        self._rectangle = rectangle
    }

    /// The default cutout rect for barcode scanning.
    public static let defaultBarcodeCutoutRect = CameraRect(
        CGPoint(x: 0.15, y: 0.6),
        CGPoint(x: 0.85, y: 0.6),
        CGPoint(x: 0.15, y: 0.4),
        CGPoint(x: 0.85, y: 0.4)
    )

    /// The default cutout rect for nutrition label scanning.
    public static let defaultLabelCutoutRect = CameraRect(
        CGPoint(x: 0.15, y: 0.8),
        CGPoint(x: 0.85, y: 0.8),
        CGPoint(x: 0.15, y: 0.2),
        CGPoint(x: 0.85, y: 0.2)
    )

    public var body: some View {
        ZStack {
            CameraCutoutShape(points: rectangle)
                .fill(Color.black, style: .init(eoFill: true))
                .opacity(0.4)

            CameraCutoutStrokeShape(lineLength: 15, points: rectangle)
                .stroke(Color.white, style: .init(lineWidth: 5, lineCap: .round))
        }
    }
}
