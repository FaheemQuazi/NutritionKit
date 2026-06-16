
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// A lightweight text fragment with an optional bounding box, consumed by the lexer.
struct TextBox {
    /// A unique identifier for this fragment.
    let id: UUID

    /// The recognized text.
    let text: String

    /// The bounding box of the text (normalized), or `.zero` when geometry is irrelevant.
    let boundingBox: CGRect

    init(text: String, boundingBox: CGRect) {
        self.id = UUID()
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Structured text extracted from a document by the Vision framework.
struct ScannedDocument {
    /// Rows of cells. A table row maps to its ordered cell transcripts; free text maps each line
    /// to a single-cell row. Used by the parser to pair labels with values within a row.
    let rows: [[String]]

    /// All recognized text lines, used for language detection.
    let lines: [String]

    var isEmpty: Bool { rows.isEmpty }
}

/// Wraps the iOS 26 `RecognizeDocumentsRequest` to extract structured rows of text from an image.
enum DocumentTextScanner {
    /// Run document recognition on an image and extract its structured rows and text lines.
    static func scan(image: CGImage,
                     orientation: CGImagePropertyOrientation = .up) async throws -> ScannedDocument {
        let request = RecognizeDocumentsRequest()
        let observations = try await request.perform(on: image, orientation: orientation)

        guard let document = observations.first?.document else {
            return ScannedDocument(rows: [], lines: [])
        }

        var rows: [[String]] = []
        var lines: [String] = []

        // Tables provide explicit row/column structure: one row per nutrient.
        for table in document.tables {
            for row in table.rows {
                let cells = row
                    .map { String($0.content.text.transcript).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                guard !cells.isEmpty else { continue }

                rows.append(cells)
                lines.append(contentsOf: cells)
            }
        }

        // Free text (paragraphs) covers list-style labels and anything outside a table.
        let textContainers = document.paragraphs.isEmpty ? [document.text] : document.paragraphs
        for container in textContainers {
            for line in container.transcript.split(whereSeparator: \.isNewline) {
                let trimmed = String(line).trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                rows.append([trimmed])
                lines.append(trimmed)
            }
        }

        return ScannedDocument(rows: rows, lines: lines)
    }
}
