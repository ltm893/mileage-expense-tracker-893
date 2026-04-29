// NetworkService.swift
// Generic API client — reads base URL from AppConfig, JWT from AuthService.
// All API calls go through one place. Swap backends by updating met_outputs.json only.

import Foundation

enum APIError: LocalizedError {
    case badURL
    case httpError(Int, String)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .badURL:                     return "Invalid URL."
        case .httpError(let code, let m): return "Server error \(code): \(m)"
        case .decodingError(let m):       return "Failed to decode response: \(m)"
        case .networkError(let m):        return "Network error: \(m)"
        }
    }
}

final class NetworkService {

    static let shared = NetworkService()

    private let config  = AppConfig.shared
    private let session = URLSession.shared

    weak var authService: AuthService?

    // MARK: - CRUD methods
    func get<T: Decodable>(_ path: String) async throws -> T {
        let req = try await buildRequest(path: path, method: "GET")
        return try await perform(req)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req  = try await buildRequest(path: path, method: "POST")
        req.httpBody = try JSONEncoder().encode(body)
        return try await perform(req)
    }

    func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req  = try await buildRequest(path: path, method: "PUT")
        req.httpBody = try JSONEncoder().encode(body)
        return try await perform(req)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        let req = try await buildRequest(path: path, method: "DELETE")
        return try await perform(req)
    }

    // MARK: - Build request
    private func buildRequest(path: String, method: String) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: config.apiBaseURL) else {
            throw APIError.badURL
        }
        var req        = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let auth = authService {
            let token = try await auth.idToken()
            req.setValue(token, forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: - Execute + decode
    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError("No HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIError.httpError(http.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}
