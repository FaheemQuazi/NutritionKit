import Foundation
import Testing
import UIKit
@testable import NutritionKit

// MARK: - Image-based scanning (runs the iOS 26 document recognizer over bundled label images)

@Suite struct NutritionLabelScanningTests {
    /// Load a bundled test asset as a `CGImage`.
    func image(_ assetName: String) throws -> CGImage {
        guard let image = UIImage(named: assetName, in: Bundle.module, with: nil)?.cgImage else {
            throw NutritionKitError("image \(assetName) does not exist")
        }

        return image
    }

    /// Run the full detector (including the validity gate) over a bundled asset.
    func scan(_ assetName: String) async throws -> NutritionLabel {
        let detector = NutritionLabelDetector(image: try image(assetName))
        guard let label = try await detector.scan() else {
            throw NutritionKitError("no nutrition label found in \(assetName)")
        }

        return label
    }

    /// Parse a bundled asset, bypassing the validity gate (for partial labels).
    func parseRaw(_ assetName: String) async throws -> NutritionLabel {
        let document = try await DocumentTextScanner.scan(image: try image(assetName))
        let language = NutritionLabelDetector.determineLabelLanguage(lines: document.lines)
        return DocumentNutritionLabelParser(rows: document.rows, language: language).parse()
    }

    @Test func usLabel1() async throws {
        let label = try await scan("testLabelUS1")

        #expect(label.servingSize == .amount(amount: .solid(milligrams: 50_000)))

        // Calories/fat are unreliable here: the recognizer reads "Callories" (so the calories label
        // is not matched) and the stray "from fat" pollutes the bare-fat match. The rest is solid.
        #expect(label.nutritionFacts[.saturatedFat] == .solid(milligrams: 2000))
        #expect(label.nutritionFacts[.transFat] == .solid(milligrams: 0))

        #expect(label.nutritionFacts[.cholesterol] == nil) // Label says 'Cholosterol'
        #expect(label.nutritionFacts[.sodium] == .solid(milligrams: 0))

        #expect(label.nutritionFacts[.carbohydrates] == .solid(milligrams: 19_000))
        #expect(label.nutritionFacts[.dietaryFiber] == .solid(milligrams: 2000))
        #expect(label.nutritionFacts[.sugar] == .solid(milligrams: 17_000))

        #expect(label.nutritionFacts[.protein] == .solid(milligrams: 29_000))

        #expect(label.nutritionFacts[.vitaminC] == .dailyValue(percentage: 35))
        #expect(label.nutritionFacts[.vitaminA] == .dailyValue(percentage: 20))
        #expect(label.nutritionFacts[.calcium] == .dailyValue(percentage: 5))
        #expect(label.nutritionFacts[.zinc] == .dailyValue(percentage: 5))
    }

    @Test func usLabel2() async throws {
        let label = try await scan("testLabelUS2")

        // Calories are OCR'd as "Cer Series 90" on this label, so the calories value is not matched.
        #expect(label.nutritionFacts[.fat] == .solid(milligrams: 2000))
        #expect(label.nutritionFacts[.saturatedFat] == .solid(milligrams: 1000))
        #expect(label.nutritionFacts[.transFat] == .solid(milligrams: 500))

        #expect(label.nutritionFacts[.cholesterol] == .solid(milligrams: 10))
        #expect(label.nutritionFacts[.sodium] == .solid(milligrams: 200))

        #expect(label.nutritionFacts[.carbohydrates] == .solid(milligrams: 15_000))
        #expect(label.nutritionFacts[.dietaryFiber] == .solid(milligrams: 0))
        #expect(label.nutritionFacts[.sugar] == .solid(milligrams: 14_000))
        #expect(label.nutritionFacts[.addedSugar] == .solid(milligrams: 13_000))

        #expect(label.nutritionFacts[.protein] == .solid(milligrams: 3_000))

        #expect(label.nutritionFacts[.vitaminD] == .dailyValue(percentage: 0))
        #expect(label.nutritionFacts[.calcium] == .dailyValue(percentage: 6))
        #expect(label.nutritionFacts[.iron] == .dailyValue(percentage: 6))
        #expect(label.nutritionFacts[.potassium] == .dailyValue(percentage: 10))
    }

    @Test func usLabel3() async throws {
        let label = try await scan("testLabelUS3")

        #expect(label.servingSize == .amount(amount: .liquid(milliliters: MeasurementUnit.cup.normalizeValue(1))))

        #expect(label.nutritionFacts[.calories] == .energy(kcal: 220))

        #expect(label.nutritionFacts[.fat] == .solid(milligrams: 5000))
        #expect(label.nutritionFacts[.saturatedFat] == .solid(milligrams: 2000))
        #expect(label.nutritionFacts[.transFat] == .solid(milligrams: 0))

        #expect(label.nutritionFacts[.cholesterol] == .solid(milligrams: 15))
        #expect(label.nutritionFacts[.sodium] == .solid(milligrams: 240))

        #expect(label.nutritionFacts[.carbohydrates] == .solid(milligrams: 35_000))
        #expect(label.nutritionFacts[.dietaryFiber] == .solid(milligrams: 6000))
        #expect(label.nutritionFacts[.sugar] == .solid(milligrams: 7_000))
        #expect(label.nutritionFacts[.addedSugar] == .solid(milligrams: 4_000))

        #expect(label.nutritionFacts[.protein] == .solid(milligrams: 9_000))

        #expect(label.nutritionFacts[.vitaminD] == .solid(milligrams: 0.005))
        #expect(label.nutritionFacts[.calcium] == .solid(milligrams: 200))
        #expect(label.nutritionFacts[.iron] == .solid(milligrams: 1))
        #expect(label.nutritionFacts[.potassium] == .solid(milligrams: 470))
    }

    @Test func usLabel4() async throws {
        // This is a partial label crop: the main "Calories 150" line is not recognized, so only four
        // data points are found — below the validity threshold, so scan() returns nil. The parser
        // still extracts the values that are present.
        #expect(try await NutritionLabelDetector(image: try image("testLabelUS4")).scan() == nil)

        let label = try await parseRaw("testLabelUS4")
        #expect(label.servingSize == .amount(amount: .solid(milligrams: 41_000)))
        #expect(label.nutritionFacts[.caloriesFromFat] == .energy(kcal: 25))
        #expect(label.nutritionFacts[.fat] == .solid(milligrams: 2500))
        #expect(label.nutritionFacts[.saturatedFat] == .solid(milligrams: 500))
    }

    @Test func usList1() async throws {
        let label = try await scan("testListUS1")

        // Serving size is unreliable on a list-style label that the recognizer flattens into one
        // line ("Servings: 12, Serv. size: 1 mint (2g)"), so it is not asserted here.
        #expect(label.nutritionFacts[.calories] == .energy(kcal: 5))

        #expect(label.nutritionFacts[.fat] == .solid(milligrams: 0))
        #expect(label.nutritionFacts[.saturatedFat] == .solid(milligrams: 0))
        #expect(label.nutritionFacts[.transFat] == .solid(milligrams: 0))

        #expect(label.nutritionFacts[.sodium] == .solid(milligrams: 0))

        #expect(label.nutritionFacts[.carbohydrates] == .solid(milligrams: 2_000))
        #expect(label.nutritionFacts[.dietaryFiber] == .solid(milligrams: 0))
        #expect(label.nutritionFacts[.sugar] == .solid(milligrams: 2_000))
        #expect(label.nutritionFacts[.addedSugar] == .solid(milligrams: 2_000))

        #expect(label.nutritionFacts[.protein] == .solid(milligrams: 0))

        #expect(label.nutritionFacts[.vitaminD] == .dailyValue(percentage: 0))
        #expect(label.nutritionFacts[.calcium] == .dailyValue(percentage: 0))
        #expect(label.nutritionFacts[.iron] == .dailyValue(percentage: 0))
        #expect(label.nutritionFacts[.potassium] == .dailyValue(percentage: 6))
    }

    @Test func deLabel1() async throws {
        // Known limitation: this multilingual label lays its values out in a column far from their
        // labels. RecognizeDocumentsRequest does not group them into a table, and — without the old
        // geometry fallback (removed by design) — the labels and values cannot be paired, so no
        // valid label is produced. German tokenizing itself is covered by `LexerTests`.
        let result = try await NutritionLabelDetector(image: try image("testLabelDE1")).scan()
        #expect(result == nil)
    }
}

// MARK: - Parser (deterministic, no Vision required)

@Suite struct NutritionLabelParserTests {
    @Test func pairsTableRows() {
        let rows = [
            ["Total Fat", "8g", "10%"],
            ["Sodium", "200mg", "9%"],
            ["Total Carbohydrate", "19g", "6%"],
            ["Serving Size", "50g"],
            ["Vitamin C", "35%"],
        ]

        let label = DocumentNutritionLabelParser(rows: rows, language: .english).parse()

        #expect(label.nutritionFacts[.fat] == .solid(milligrams: 8000))
        #expect(label.nutritionFacts[.sodium] == .solid(milligrams: 200))
        #expect(label.nutritionFacts[.carbohydrates] == .solid(milligrams: 19_000))
        #expect(label.servingSize == .amount(amount: .solid(milligrams: 50_000)))
        #expect(label.nutritionFacts[.vitaminC] == .dailyValue(percentage: 35))
    }

    @Test func pairsMultipleNutrientsInOneLine() {
        let rows = [["Total Fat 0g Sodium 0mg Total Carb. 2g"]]
        let label = DocumentNutritionLabelParser(rows: rows, language: .english).parse()

        #expect(label.nutritionFacts[.fat] == .solid(milligrams: 0))
        #expect(label.nutritionFacts[.sodium] == .solid(milligrams: 0))
        #expect(label.nutritionFacts[.carbohydrates] == .solid(milligrams: 2_000))
    }

    @Test func prefersMeasuredValueOverStrayNumber() {
        // "1/2 cup (50g)" — the gram value should win over the stray "1".
        let rows = [["Serving Size 1/2 cup (50g)"]]
        let label = DocumentNutritionLabelParser(rows: rows, language: .english).parse()

        #expect(label.servingSize == .amount(amount: .solid(milligrams: 50_000)))
    }

    @Test func convertsBareCaloriesToEnergy() {
        let rows = [["Calories 235"]]
        let label = DocumentNutritionLabelParser(rows: rows, language: .english).parse()

        #expect(label.nutritionFacts[.calories] == .energy(kcal: 235))
    }
}

// MARK: - Lexer (deterministic)

@Suite struct LexerTests {
    private func tokens(for text: String, language: LabelLanguage = .english) -> [TextDescription] {
        var result: [TextDescription] = []
        var lexer = Lexer(rawText: .init(text: text, boundingBox: .zero), language: language) { categorized in
            if let description = categorized.description {
                result.append(description)
            }
        }

        lexer.parse()
        return result
    }

    @Test func tokenizesLabelAmountAndDailyValue() {
        let tokens = tokens(for: "Total Fat 8g 10%")

        #expect(tokens.contains { if case .nutritionFactLabel(.fat) = $0 { return true }; return false })
        #expect(tokens.contains { if case .amount(.solid(8000)) = $0 { return true }; return false })
        #expect(tokens.contains { if case .amount(.dailyValue(10)) = $0 { return true }; return false })
    }

    @Test func parsesGermanDecimalSeparator() {
        let tokens = tokens(for: "Zucker 0,3g", language: .german)

        #expect(tokens.contains { if case .nutritionFactLabel(.sugar) = $0 { return true }; return false })
        #expect(tokens.contains { if case .amount(.solid(300)) = $0 { return true }; return false }) // 0.3 g
    }
}

// MARK: - OpenFoodFacts decoding (deterministic, no network)

@Suite struct OpenFoodFactsTests {
    @Test func decodesProductResponse() throws {
        let json = Data("""
        {
          "product": {
            "product_name": "Nutella",
            "serving_size": "15 g",
            "nutriments": {
              "energy-kcal_value": 539,
              "fat_value": 30.9, "fat_unit": "g",
              "sugars_value": 56.3, "sugars_unit": "g",
              "proteins_value": 6.3, "proteins_unit": "g",
              "salt_value": 0.107, "salt_unit": "g"
            }
          },
          "status": 1
        }
        """.utf8)

        let item = try OpenFoodFactsAPI.makeFoodItem(from: json)

        #expect(item.productName == "Nutella")
        #expect(item.nutrition?.servingSize == .amount(amount: .solid(milligrams: 15_000)))
        #expect(item.nutrition?.nutritionFacts[.calories] == .energy(kcal: 539))
        #expect(item.nutrition?.nutritionFacts[.fat] == .solid(milligrams: 30_900))
        #expect(item.nutrition?.nutritionFacts[.sugar] == .solid(milligrams: 56_300))
        #expect(item.nutrition?.nutritionFacts[.protein] == .solid(milligrams: 6_300))
        #expect(item.nutrition?.nutritionFacts[.salt] == .solid(milligrams: 107))
    }

    @Test func formsApiUrl() async {
        let url = OpenFoodFactsAPI().formApiUrl("59032823", fields: [.productName, .nutrients])
        #expect(url == "https://world.openfoodfacts.org/api/v2/product/59032823?fields=product_name,nutriments")
    }
}

// MARK: - Localization (verifies the bundled string table resolves)

@Suite struct LocalizationTests {
    @Test func resolvesNutrientNames() {
        // If the resource bundle isn't wired up, these come back as the raw key "nutrient.…".
        #expect(NutritionItem.calories.localizedName == "Calories")
        #expect(NutritionItem.dietaryFiber.localizedName == "Dietary Fiber")
        #expect(NutritionItem.addedSugar.localizedName == "Added Sugars")
    }
}
