
import Foundation

public struct FoodItem: Sendable {
    /// The name of this product.
    public var productName: String?

    /// The nutritional facts for this food item.
    public var nutrition: NutritionLabel?

    public init(productName: String?, nutrition: NutritionLabel?) {
        self.productName = productName
        self.nutrition = nutrition
    }
}

// MARK: Hashable & Codable

extension FoodItem: Codable {
    enum CodingKeys: String, CodingKey {
        case productName, nutrition
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(productName, forKey: .productName)
        try container.encode(nutrition, forKey: .nutrition)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            productName: try container.decode(Optional<String>.self, forKey: .productName),
            nutrition: try container.decode(Optional<NutritionLabel>.self, forKey: .nutrition)
        )
    }
}

extension FoodItem: Equatable {
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return (
            lhs.productName == rhs.productName
            && lhs.nutrition == rhs.nutrition
        )
    }
}

extension FoodItem: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(productName)
        hasher.combine(nutrition)
    }
}


