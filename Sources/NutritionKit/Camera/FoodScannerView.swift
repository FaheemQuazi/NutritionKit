
import os
import SwiftUI

/// A view that scans a barcode and looks up the corresponding food item from OpenFoodFacts.
public struct FoodScannerView: View {
    /// The most recently scanned food item.
    @Binding var foodItem: FoodItem?

    @State private var camera = CameraManager()
    @State private var cameraRectangle = DefaultCameraOverlayView.defaultBarcodeCutoutRect
    @State private var isProcessing = false

    public init(foodItem: Binding<FoodItem?>) {
        self._foodItem = foodItem
    }

    public var body: some View {
        AnyCameraView(camera: camera) {
            DefaultCameraOverlayView(rectangle: $cameraRectangle)
        }
        .task {
            await camera.start()
            for await frame in camera.frames {
                guard foodItem == nil, !isProcessing else { continue }
                guard let barcode = await BarcodeDetector.detect(in: frame) else { continue }

                await lookUp(barcode)
            }
        }
        .onDisappear {
            camera.stop()
        }
    }

    private func lookUp(_ barcode: Barcode) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            foodItem = try await OpenFoodFactsAPI.shared.find(barcode.data)
        }
        catch {
            Logger.nutritionKit.error("looking up food item failed: \(error.localizedDescription)")
        }
    }
}
