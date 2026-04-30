// ReceiptScanner.swift
// On-device receipt OCR using Apple's Vision framework.
// Scans a receipt image and extracts total amount, date, and merchant name.

import Vision
import UIKit

struct ReceiptScanResult {
    var amount:   String?
    var date:     String?
    var merchant: String?
}

final class ReceiptScanner {

    static func scan(_ image: UIImage) async -> ReceiptScanResult {
        guard let cgImage = image.cgImage else { return ReceiptScanResult() }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: ReceiptScanResult())
                    return
                }
                let lines  = observations.compactMap { $0.topCandidates(1).first?.string }
                let result = extractFields(from: lines)
                continuation.resume(returning: result)
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Extract fields
    private static func extractFields(from lines: [String]) -> ReceiptScanResult {
        var result = ReceiptScanResult()

        // ── Amount ────────────────────────────────────────────────────────────
        let totalKeywords = ["total", "amount due", "balance due", "grand total",
                             "subtotal", "amount", "due", "charge"]
        var allAmounts: [(value: Double, lineIndex: Int)] = []

        for (index, line) in lines.enumerated() {
            for amount in extractAmounts(from: line) {
                allAmounts.append((value: amount, lineIndex: index))
            }
        }

        // First try: line with a total keyword
        outer: for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard totalKeywords.contains(where: { lower.contains($0) }) else { continue }
            if let amount = extractAmounts(from: line).first {
                result.amount = formatAmount(amount); break outer
            }
            if index + 1 < lines.count,
               let amount = extractAmounts(from: lines[index + 1]).first {
                result.amount = formatAmount(amount); break outer
            }
        }

        // Fallback: largest dollar value on the receipt
        if result.amount == nil,
           let largest = allAmounts.max(by: { $0.value < $1.value }) {
            result.amount = formatAmount(largest.value)
        }

        // ── Date — 4-digit year only (19xx or 20xx) to avoid "0026" misreads ──
        let datePatterns = [
            #"\d{1,2}[/\-]\d{1,2}[/\-](19|20)\d{2}"#,  // 04/29/2026
            #"(19|20)\d{2}[/\-]\d{1,2}[/\-]\d{1,2}"#,  // 2026-04-29
            #"\w+ \d{1,2},? (19|20)\d{2}"#,             // April 29, 2026
            #"\d{1,2} \w+ (19|20)\d{2}"#,               // 29 April 2026
        ]

        for line in lines {
            for pattern in datePatterns {
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let dateStr = String(line[match])
                    result.date = dateStr
                    break
                }
            }
            if result.date != nil { break }
        }

        // ── Merchant — first meaningful line near top ──────────────────────────
        let skipKeywords = ["street", "st.", "ave", "blvd", "rd.", "suite", "ste",
                            "phone", "tel", "www.", ".com", "thank you", "receipt",
                            "transaction", "store", "#", "manager"]

        for line in lines.prefix(6) {
            let lower    = line.lowercased()
            let isSkip   = skipKeywords.contains(where: { lower.contains($0) })
            let isNumber = line.allSatisfy { $0.isNumber || "()-".contains($0) }
            let tooShort = line.trimmingCharacters(in: .whitespaces).count < 3

            if !isSkip && !isNumber && !tooShort {
                result.merchant = line.trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return result
    }

    // MARK: - Extract dollar amounts
    private static func extractAmounts(from text: String) -> [Double] {
        let pattern = #"[$€£]?\d{1,6}[.,]\d{2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            let raw = String(text[matchRange])
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: "£", with: "")
                .replacingOccurrences(of: ",", with: ".")
            return Double(raw).flatMap { $0 > 0 ? $0 : nil }
        }
    }

    private static func formatAmount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
