
import os
import SwiftUI

/// A view that scans a nutrition label from the live camera feed and parses it.
public struct NutritionLabelScannerView: View {
    /// The scanned nutrition label.
    @Binding var label: NutritionLabel?

    @State private var camera = CameraManager()
    @State private var cameraRectangle = DefaultCameraOverlayView.defaultLabelCutoutRect

    public init(label: Binding<NutritionLabel?>) {
        self._label = label
    }

    public var body: some View {
        AnyCameraView(camera: camera) {
            DefaultCameraOverlayView(rectangle: $cameraRectangle)
        }
        .task {
            await camera.start()
            for await frame in camera.frames {
                guard label == nil else { break }

                if let scanned = await Self.scan(frame: frame) {
                    label = scanned
                    break
                }
            }
        }
        .onDisappear {
            camera.stop()
        }
    }

    /// Convert a frame and run the nutrition label detector off the main actor.
    private static func scan(frame: CapturedFrame) async -> NutritionLabel? {
        guard let cgImage = CameraImage.cgImage(from: frame.pixelBuffer) else {
            return nil
        }

        let detector = NutritionLabelDetector(image: cgImage, orientation: frame.orientation)
        return try? await detector.scan()
    }
}
