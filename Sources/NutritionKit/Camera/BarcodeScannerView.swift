
import CoreGraphics
import SwiftUI

public struct Barcode: Codable, Hashable, Sendable {
    /// The barcode data.
    public let data: String

    /// The corners of the barcode (normalized, Vision coordinate space).
    public let corners: [CGPoint]

    public init(data: String, corners: [CGPoint]) {
        self.data = data
        self.corners = corners
    }
}

/// A view that shows the live camera feed and reports detected barcodes.
public struct BarcodeScannerView: View {
    /// The most recently detected barcode.
    @Binding var barcodeData: Barcode?

    @State private var camera = CameraManager()
    @State private var cameraRectangle = DefaultCameraOverlayView.defaultBarcodeCutoutRect

    public init(barcodeData: Binding<Barcode?>) {
        self._barcodeData = barcodeData
    }

    public var body: some View {
        AnyCameraView(camera: camera) {
            DefaultCameraOverlayView(rectangle: $cameraRectangle)
        }
        .task {
            await camera.start()
            for await frame in camera.frames {
                if let barcode = await BarcodeDetector.detect(in: frame) {
                    barcodeData = barcode
                }
            }
        }
        .onDisappear {
            camera.stop()
        }
    }
}
