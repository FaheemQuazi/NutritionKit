
import Foundation

public actor OpenFoodFactsAPI {
    public enum Error: Swift.Error {
        case invalidUrl
        case dataNotFound
        case decodingError
    }

    public enum ProductFields: String, CaseIterable, Sendable {
        // Metadata
        case productName = "product_name"

        // Nutrition info
        case energyKcal = "energy-kcal_value"
        case servingSize = "serving_size"
        case nutrients = "nutriments"
    }

    /// The product fields to request from the API.
    private var productFields: [ProductFields]

    /// The base API URL.
    static let openFoodFactsApiUrl = "https://world.openfoodfacts.org/api/v2/product"

    /// The User-Agent identifying this client to the OpenFoodFacts API.
    static let userAgent = "NutritionKit - iOS - Version 2.0"

    /// Shared instance.
    public static let shared = OpenFoodFactsAPI()

    /// Default initializer.
    public init() {
        self.productFields = ProductFields.allCases
    }

    /// Update the API configuration.
    public func configure(productFields: [ProductFields]? = nil) {
        if let productFields {
            self.productFields = productFields
        }
    }

    /// Load info about a food item with the given barcode.
    public func find(_ barcode: String) async throws -> FoodItem {
        guard let url = URL(string: self.formApiUrl(barcode)) else {
            throw Error.invalidUrl
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        }
        catch {
            throw Error.dataNotFound
        }

        return try Self.makeFoodItem(from: data)
    }

    /// Decode an API response payload into a food item. Exposed for testing without a network call.
    static func makeFoodItem(from data: Data) throws -> FoodItem {
        let response: ProductResponse
        do {
            response = try JSONDecoder().decode(ProductResponse.self, from: data)
        }
        catch {
            throw Error.decodingError
        }

        guard let product = response.product else {
            throw Error.dataNotFound
        }

        return createFoodItem(from: product)
    }

    /// Create a food item from the decoded API response.
    private static func createFoodItem(from product: Product) -> FoodItem {
        let nutriments = product.nutriments ?? Nutriments(values: [:])

        // Parse the free-text serving size using the lexer.
        var servingSize: ServingSize? = nil
        if let rawServingSize = product.servingSize {
            var lexer = Lexer(rawText: .init(text: rawServingSize, boundingBox: .zero), language: .english) { categorizedText in
                if case .amount(let value) = categorizedText.description {
                    servingSize = .amount(amount: value)
                }
            }

            lexer.parse()
        }

        var nutritionFacts = [NutritionItem: NutritionAmount]()
        if let calories = nutriments.double(ProductFields.energyKcal.rawValue) {
            nutritionFacts[.calories] = .energy(kcal: calories)
        }

        for fact in NutritionItem.allCases {
            guard let amount = Self.readNutritionItem(fact, from: nutriments) else {
                continue
            }

            nutritionFacts[fact] = amount
        }

        return .init(productName: product.productName,
                     nutrition: NutritionLabel(language: .english,
                                               servingSize: servingSize,
                                               nutritionFacts: nutritionFacts))
    }

    private static func readNutritionItem(_ item: NutritionItem, from nutriments: Nutriments) -> NutritionAmount? {
        guard let key = item.openFoodFactsKey else { return nil }
        guard let value = nutriments.double("\(key)_value") else { return nil }
        guard let unitSpelling = nutriments.string("\(key)_unit") else { return nil }

        for (unit, spellings) in MeasurementUnit.knownSpellingsEnglish where spellings.contains(unitSpelling) {
            return .init(amount: value, unit: unit)
        }

        return nil
    }

    /// Create the API URL for a given barcode.
    public nonisolated func formApiUrl(_ barcode: String, fields: [ProductFields]) -> String {
        let fieldList = fields
            .map { $0.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.rawValue }
            .joined(separator: ",")

        return "\(Self.openFoodFactsApiUrl)/\(barcode)?fields=\(fieldList)"
    }

    /// Create the API URL for a given barcode using the configured fields.
    func formApiUrl(_ barcode: String) -> String {
        self.formApiUrl(barcode, fields: self.productFields)
    }
}

// MARK: - Decodable response model

private struct ProductResponse: Decodable {
    let product: Product?
    let status: Int?
}

private struct Product: Decodable {
    let productName: String?
    let servingSize: String?
    let nutriments: Nutriments?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case servingSize = "serving_size"
        case nutriments
    }
}

/// The dynamic `nutriments` dictionary, whose values may be numbers or strings.
private struct Nutriments: Decodable {
    let values: [String: NutrimentValue]

    init(values: [String: NutrimentValue]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.values = (try? container.decode([String: NutrimentValue].self)) ?? [:]
    }

    func double(_ key: String) -> Double? { values[key]?.doubleValue }
    func string(_ key: String) -> String? { values[key]?.stringValue }
}

private enum NutrimentValue: Decodable {
    case number(Double)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        }
        else if let value = try? container.decode(Double.self) {
            self = .number(value)
        }
        else if let value = try? container.decode(String.self) {
            self = .string(value)
        }
        else {
            self = .null
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        case .null: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .null: return nil
        }
    }
}

fileprivate extension NutritionItem {
    /// The equivalent key for the OpenFoodFacts API.
    var openFoodFactsKey: String? {
        switch self {
        case .calories:
            return "energy_kcal"
        case .caloriesFromFat:
            return nil
        case .fat:
            return "fat"
        case .saturatedFat:
            return "saturated-fat"
        case .unsaturatedFat:
            return nil
        case .monounsaturatedFat:
            return "monounsaturated-fat"
        case .polyunsaturatedFat:
            return "polyunsaturated-fat"
        case .omega3FattyAcids:
            return "omega-3-fat"
        case .transFat:
            return "trans-fat"
        case .carbohydrates:
            return "carbohydrates"
        case .sugar:
            return "sugars"
        case .addedSugar:
            return nil
        case .sugarAlcohols:
            return nil
        case .starch:
            return "starch"
        case .dietaryFiber:
            return "fiber"
        case .protein:
            return "proteins"
        case .salt:
            return "salt"
        case .sodium:
            return "sodium"
        case .cholesterol:
            return "cholesterol"
        case .vitaminA:
            return "vitamin-a"
        case .vitaminB1:
            return "vitamin-b1"
        case .vitaminB2:
            return "vitamin-b2"
        case .vitaminB6:
            return "vitamin-b6"
        case .vitaminB9:
            return "vitamin-b9"
        case .vitaminB12:
            return "vitamin-b12"
        case .vitaminC:
            return "vitamin-c"
        case .vitaminD:
            return "vitamin-d"
        case .vitaminE:
            return "vitamin-e"
        case .vitaminK:
            return "vitamin-k"
        case .caffeine:
            return "caffeine"
        case .taurine:
            return "taurine"
        case .alcohol:
            return "alcohol"
        case .magnesium:
            return "magnesium"
        case .calcium:
            return "calcium"
        case .zinc:
            return "zinc"
        case .potassium:
            return "potassium"
        case .iron:
            return "iron"
        case .fluoride:
            return "fluoride"
        case .copper:
            return "copper"
        case .chloride:
            return "chloride"
        case .phosphorus:
            return "phosphorus"
        case .iodine:
            return "iodine"
        case .chromium:
            return "chromium"
        }
    }
}
