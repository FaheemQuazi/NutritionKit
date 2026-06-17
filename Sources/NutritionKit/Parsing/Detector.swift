
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Detects and parses a nutrition label from an image using the Vision document recognizer.
public struct NutritionLabelDetector {
    /// The image to scan.
    let image: CGImage

    /// The orientation of the image.
    let orientation: CGImagePropertyOrientation

    /// Default initializer.
    public init(image: CGImage, orientation: CGImagePropertyOrientation = .up) {
        self.image = image
        self.orientation = orientation
    }

    /// Scan the image for a nutrition label and parse it.
    ///
    /// - Returns: The parsed label, or `nil` if no label with sufficient data was found.
    public func scan() async throws -> NutritionLabel? {
        let document = try await DocumentTextScanner.scan(image: image, orientation: orientation)
        guard !document.isEmpty else {
            return nil
        }

        let language = Self.determineLabelLanguage(lines: document.lines)
        let parser = DocumentNutritionLabelParser(rows: document.rows, language: language)
        let label = parser.parse()

        guard label.isValid else {
            return nil
        }

        return label
    }

    /// Try to determine the language of the label from its recognized text.
    static func determineLabelLanguage(lines: [String]) -> LabelLanguage {
        let keywords = KnownLabel.keywordsByLanguage
        var scoreByLanguage = [LabelLanguage: Int]()

        for line in lines {
            let searchText = line.lowercased()
            for (language, keywords) in keywords {
                let score = keywords.filter { searchText.contains($0) }.count
                scoreByLanguage[language] = (scoreByLanguage[language] ?? 0) + score
            }
        }

        return scoreByLanguage.max { $0.value < $1.value }?.key ?? .english
    }
}
