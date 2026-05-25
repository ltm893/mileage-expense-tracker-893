// ReceiptUploader.swift
// Fetches a pre-signed S3 URL from the API then PUTs the image directly to S3.

import Foundation
import UIKit

struct ReceiptUploader {

    static func upload(
        image:      UIImage,
        expenseId:  String,
        api:        NetworkService
    ) async throws -> String {

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.badURL)
        }

        // 1. Ask our API for a pre-signed PUT URL
        let response: UploadURLResponse = try await api.get(
            "expenses?uploadUrl=1&expenseId=\(expenseId)"
        )

        // 2. PUT the image directly to S3 using the pre-signed URL
        var request        = URLRequest(url: URL(string: response.uploadUrl)!)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody   = imageData

        let (_, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return response.s3Key
    }
}

struct UploadURLResponse: Decodable {
    let uploadUrl: String
    let s3Key:     String
}
