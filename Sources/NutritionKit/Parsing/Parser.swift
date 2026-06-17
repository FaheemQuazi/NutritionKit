
import CoreGraphics
import Foundation

enum TextDescription {
    /// This text refers to a nutrition fact label.
    case nutritionFactLabel(fact: NutritionItem)

    /// This text refers to an amount.
    case amount(value: NutritionAmount)

    /// This text describes a serving size.
    case servingSize(value: ServingSize)

    /// A known label.
    case knownLabel(label: KnownLabel)

    /// Unknown text.
    case uncategorized(text: String)
}

struct CategorizedText {
    /// The ID of this text label.
    let id = UUID()

    /// The category of this text.
    let description: TextDescription?

    /// The raw text instance this belongs to.
    let rawText: TextBox
}

/// Parses a nutrition label from rows of recognized text. Each row's cells are tokenized with the
/// `Lexer`; within a row, each value is assigned to its nearest label and the best-matching value
/// per label is kept.
final class DocumentNutritionLabelParser {
    /// The rows of recognized text (table rows or single-cell text lines).
    let rows: [[String]]

    /// The language to use for parsing.
    let language: LabelLanguage

    init(rows: [[String]], language: LabelLanguage) {
        self.rows = rows
        self.language = language
    }

    /// The target a label token refers to.
    private enum LabelTarget: Equatable {
        case fact(NutritionItem)
        case servingSize
    }

    /// A label or amount token in reading order within a row.
    private enum Token {
        case label(LabelTarget)
        case amount(NutritionAmount)
    }

    func parse() -> NutritionLabel {
        var nutritionFacts = [NutritionItem: NutritionAmount]()
        var servingSize: ServingSize? = nil

        let tokenRows = Self.mergeOrphanRows(rows.map { self.tokenize(row: $0) })
        for tokens in tokenRows {
            self.pair(tokens: tokens, into: &nutritionFacts, servingSize: &servingSize)
        }

        return .init(language: language, servingSize: servingSize, nutritionFacts: nutritionFacts)
    }

    /// Tokenize all cells of a row in reading order, keeping only label and amount tokens.
    private func tokenize(row: [String]) -> [Token] {
        var tokens: [Token] = []

        for cell in row {
            var lexer = Lexer(rawText: .init(text: cell, boundingBox: .zero), language: language) { categorized in
                switch categorized.description {
                case .nutritionFactLabel(let fact):
                    tokens.append(.label(.fact(fact)))
                case .knownLabel(let label):
                    if case .servingSize = label {
                        tokens.append(.label(.servingSize))
                    }
                case .amount(let value):
                    tokens.append(.amount(value))
                case .servingSize, .uncategorized, .none:
                    break
                }
            }

            lexer.parse()
        }

        return tokens
    }

    /// Merge a row that has labels but no values with the following values-only row. This reconnects
    /// labels and values that the recognizer split across rows (e.g. "Serving size" / "1 cup (255g)").
    private static func mergeOrphanRows(_ tokenRows: [[Token]]) -> [[Token]] {
        func hasLabel(_ tokens: [Token]) -> Bool { tokens.contains { if case .label = $0 { return true }; return false } }
        func hasAmount(_ tokens: [Token]) -> Bool { tokens.contains { if case .amount = $0 { return true }; return false } }

        var result: [[Token]] = []
        var index = 0
        while index < tokenRows.count {
            let current = tokenRows[index]
            if hasLabel(current), !hasAmount(current), index + 1 < tokenRows.count {
                let next = tokenRows[index + 1]
                if hasAmount(next), !hasLabel(next) {
                    result.append(current + next)
                    index += 2
                    continue
                }
            }

            result.append(current)
            index += 1
        }

        return result
    }

    /// Assign each value in the row to its nearest label and keep the best value per label.
    private func pair(tokens: [Token],
                      into nutritionFacts: inout [NutritionItem: NutritionAmount],
                      servingSize: inout ServingSize?) {
        let labels: [(index: Int, target: LabelTarget)] = tokens.enumerated().compactMap { index, token in
            guard case .label(let target) = token else { return nil }
            return (index, target)
        }

        guard !labels.isEmpty else { return }

        let amounts: [(index: Int, value: NutritionAmount)] = tokens.enumerated().compactMap { index, token in
            guard case .amount(let value) = token else { return nil }
            return (index, value)
        }

        // Assign each amount to its nearest label (ties prefer the preceding label).
        var amountsByLabel: [Int: [(index: Int, value: NutritionAmount)]] = [:]
        for amount in amounts {
            guard let labelIndex = Self.nearestLabelIndex(toAmountAt: amount.index, labels: labels) else { continue }
            amountsByLabel[labelIndex, default: []].append(amount)
        }

        // Pick the best value for each label.
        for label in labels {
            let candidates = (amountsByLabel[label.index] ?? []).filter { Self.isCompatible(label.target, $0.value) }
            let chosen = candidates.min { lhs, rhs in
                if lhs.value.precedence != rhs.value.precedence {
                    return lhs.value.precedence > rhs.value.precedence
                }

                return abs(lhs.index - label.index) < abs(rhs.index - label.index)
            }

            guard let chosen else { continue }
            self.apply(target: label.target, amount: chosen.value, into: &nutritionFacts, servingSize: &servingSize)
        }
    }

    /// The index of the label nearest to an amount; ties prefer the preceding label.
    private static func nearestLabelIndex(toAmountAt amountIndex: Int,
                                          labels: [(index: Int, target: LabelTarget)]) -> Int? {
        var bestIndex: Int? = nil
        var bestDistance = Int.max

        // Labels are in ascending order, so a strict `<` keeps the first (preceding) label on a tie.
        for label in labels {
            let distance = abs(label.index - amountIndex)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = label.index
            }
        }

        return bestIndex
    }

    /// Whether an amount is a plausible value for a label. Calories are only ever an energy or a
    /// bare number, never a mass, volume or % daily value.
    private static func isCompatible(_ target: LabelTarget, _ amount: NutritionAmount) -> Bool {
        switch target {
        case .fact(.calories), .fact(.caloriesFromFat):
            switch amount {
            case .energy, .unitless:
                return true
            default:
                return false
            }
        default:
            return true
        }
    }

    private func apply(target: LabelTarget,
                       amount: NutritionAmount,
                       into nutritionFacts: inout [NutritionItem: NutritionAmount],
                       servingSize: inout ServingSize?) {
        switch target {
        case .fact(let fact):
            var amount = amount

            // Calories are sometimes printed as a bare number; treat them as an energy amount.
            if fact == .calories || fact == .caloriesFromFat, case .unitless(let value) = amount {
                amount = .energy(kcal: value)
            }

            // Keep the highest-precedence value if this fact was already detected.
            if let existing = nutritionFacts[fact], existing.precedence >= amount.precedence {
                return
            }

            nutritionFacts[fact] = amount
        case .servingSize:
            if let existing = servingSize, case .amount(let existingAmount) = existing,
               existingAmount.precedence >= amount.precedence {
                return
            }

            servingSize = .amount(amount: amount)
        }
    }
}
