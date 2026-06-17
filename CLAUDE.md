# NutritionKit — guidance for Claude

A SwiftUI library for food/nutrition apps: OpenFoodFacts lookup, barcode scanning, nutrition-label
scanning + parsing, and label rendering. **iOS 26+, Swift 6** (language mode + complete strict
concurrency), **no third-party dependencies** — keep it that way; reimplement small helpers natively
rather than adding packages.

## Architecture

| Area | Path | Notes |
|---|---|---|
| Camera capture | `Sources/NutritionKit/Camera/CameraManager.swift` | `@Observable @MainActor`; `AVCaptureSession` → `AsyncStream<CapturedFrame>` (newest-1 buffering). |
| Scanner views | `Camera/BarcodeScannerView`, `FoodScannerView`, `NutritionLabelScannerView` | Each owns a `CameraManager`, consumes `frames` in `.task`, processes off-main, sets a `@Binding` result. |
| Camera UI helpers | `Camera/CameraView.swift` | Preview `UIViewRepresentable`, status container, cutout overlay shapes, `BarcodeDetector`, `CameraImage`. |
| Document OCR | `Vision/DocumentScanner.swift` | Wraps iOS 26 `RecognizeDocumentsRequest` → `ScannedDocument` (`rows: [[String]]`, `lines`). Defines `TextBox` used by the Lexer. |
| Tokenizer | `Parsing/Lexer.swift` | Char-by-char: text → `.nutritionFactLabel` / `.amount` / `.knownLabel` / `.uncategorized`. Language-aware (EN/DE), decimal separator, unit spellings. |
| Parser | `Parsing/Parser.swift` | `DocumentNutritionLabelParser`: per-row pairing (see below). |
| Detector | `Parsing/Detector.swift` | `NutritionLabelDetector.scan()` — document scan → language detect → parse → validity gate. Public entry point. |
| Data models | `Data/` | `FoodItem`, `NutritionLabel`, `NutritionItem`, `NutritionAmount`, `ServingSize`, `MeasurementUnit`, `Language` (label/unit dictionaries). |
| OpenFoodFacts | `OpenFoodFacts/OpenFoodFactsAPI.swift` | `actor`; async `URLSession.data` + `Codable`. `makeFoodItem(from:)` is the testable decode seam. |
| Rendering | `Display/USNutritionLabelView.swift` | SwiftUI nutrition-facts label. |
| Support | `Support/` | `Geometry` (CGPoint/`CameraRect` vector math), `Support` (`NutritionKitError`, `NumberFormatting`), `NutritionKit.swift` (`Logger.nutritionKit`). |
| Resources | `Resources/*.lproj/Localizable.strings`, `PrivacyInfo.xcprivacy` | EN/DE nutrient names; privacy manifest. |

## Parsing model (the core domain logic)

`RecognizeDocumentsRequest` yields table rows and text lines. For each row, the Lexer tokenizes every
cell in reading order, then pairing:

1. Assign each amount to its **nearest label** (ties prefer the *preceding* label).
2. Per label, keep the **highest-precedence compatible** amount (a measured g/mg/ml/kcal outranks a
   bare number, which outranks a % daily value); tie → nearest.
3. **Calories/caloriesFromFat** only accept energy or a bare number (never mass/volume/%DV); a bare
   number is converted to energy.
4. Orphan rows are merged: a labels-only row joins the following values-only row (reconnects
   "Serving size" / "1 cup (255g)").

There is **no geometry/spatial fallback** — it was deliberately removed in favor of the native
document recognizer. Labels and values that the recognizer places far apart (some multilingual
labels) won't pair; that's an accepted tradeoff.

## Conventions / gotchas

- **Swift 6 strict concurrency**: public value types that cross actor/task boundaries must be
  `Sendable`, and the conformance must live in the **same file** as the type (not a central file).
- **Public surface**: result types (`FoodItem`, `NutritionLabel`) expose `public` stored properties
  and inits — consumers read scan/lookup results directly.
- **Camera concurrency**: frames cross isolation via `CapturedFrame` (`@unchecked Sendable`); Vision
  runs off the main actor; only `Sendable` results hop back to `@MainActor`.
- **Localization**: nutrient display names resolve through `Bundle.module` + `Localizable.strings`.
  Adding a `NutritionItem` case means touching: the enum, `category`, `knownLabelsEnglish/German`,
  the OpenFoodFacts key map, **both** `.lproj/Localizable.strings`, and the ordering in
  `USNutritionLabelView`.
- Known OCR quirk: the bare `"fat"` spelling matches `"from fat"` inside a calories line, which can
  pollute the fat value when OCR mangles "Calories".

## Building & testing

This is an **iOS-only** package (UIKit/AVFoundation/VisionKit), so `swift build` on macOS will not
work — build and test through an **iOS Simulator destination** with `xcodebuild` (pick a current
device/OS; don't hardcode). Tooling specifics for this machine, if any, are in Claude's local memory.

- Tests use **Swift Testing** (`@Suite`/`@Test`/`#expect`).
- The deterministic suites (`NutritionLabelParserTests`, `LexerTests`, `OpenFoodFactsTests`,
  `LocalizationTests`) need no camera or network — prefer adding logic coverage there.
- `NutritionLabelScanningTests` runs the real recognizer over `Tests/.../TestAssets.xcassets` images.
  These are coupled to the OCR engine: when they drift, **dump the document rows / parsed output and
  re-baseline to truth** rather than guessing. Some assertions are intentionally relaxed with
  explanatory comments where a specific scan mis-reads text.
- Live camera scanning can only be verified on a physical device.

## Git

Default branch is `main`. Don't commit/push unless asked; branch before committing on `main`.
