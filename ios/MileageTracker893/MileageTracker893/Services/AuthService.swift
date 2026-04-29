// AuthService.swift
import Foundation
import Combine

enum AuthError: LocalizedError {
    case invalidCredentials
    case noToken
    case networkError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:    return "Incorrect email or password."
        case .noToken:               return "Not signed in."
        case .networkError(let m):   return "Network error: \(m)"
        case .unknown(let m):        return m
        }
    }
}

@MainActor
final class AuthService: ObservableObject {

    @Published var isSignedIn:    Bool    = false
    @Published var errorMessage:  String? = nil

    private let config  = AppConfig.shared
    private let session = URLSession.shared

    private let kIdToken      = "met893.idToken"
    private let kAccessToken  = "met893.accessToken"
    private let kRefreshToken = "met893.refreshToken"

    init() {
        isSignedIn = loadToken(key: kIdToken) != nil
    }

    // MARK: - Sign In
    func signIn(email: String, password: String) async throws {
        let body: [String: Any] = [
            "AuthFlow": "USER_PASSWORD_AUTH",
            "AuthParameters": ["USERNAME": email, "PASSWORD": password],
            "ClientId": config.appClientId
        ]
        let result = try await cognitoRequest(target: "InitiateAuth", body: body)

        guard
            let authResult   = result["AuthenticationResult"] as? [String: Any],
            let idToken      = authResult["IdToken"]          as? String,
            let accessToken  = authResult["AccessToken"]      as? String,
            let refreshToken = authResult["RefreshToken"]     as? String
        else { throw AuthError.invalidCredentials }

        saveToken(key: kIdToken,      value: idToken)
        saveToken(key: kAccessToken,  value: accessToken)
        saveToken(key: kRefreshToken, value: refreshToken)
        isSignedIn = true
    }

    // MARK: - Sign Out
    func signOut() {
        deleteToken(key: kIdToken)
        deleteToken(key: kAccessToken)
        deleteToken(key: kRefreshToken)
        isSignedIn    = false
        errorMessage  = nil
    }

    // MARK: - Get current ID token (auto-refreshes if expired)
    func idToken() async throws -> String {
        if let token = loadToken(key: kIdToken), !isTokenExpired(token) {
            return token
        }
        if let refreshToken = loadToken(key: kRefreshToken) {
            return try await refresh(refreshToken: refreshToken)
        }
        signOut()
        throw AuthError.noToken
    }

    // MARK: - Refresh
    private func refresh(refreshToken: String) async throws -> String {
        let body: [String: Any] = [
            "AuthFlow": "REFRESH_TOKEN_AUTH",
            "AuthParameters": ["REFRESH_TOKEN": refreshToken],
            "ClientId": config.appClientId
        ]
        let result = try await cognitoRequest(target: "InitiateAuth", body: body)

        guard
            let authResult  = result["AuthenticationResult"] as? [String: Any],
            let idToken     = authResult["IdToken"]          as? String,
            let accessToken = authResult["AccessToken"]      as? String
        else { signOut(); throw AuthError.noToken }

        saveToken(key: kIdToken,     value: idToken)
        saveToken(key: kAccessToken, value: accessToken)
        return idToken
    }

    // MARK: - Cognito REST call
    private func cognitoRequest(target: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: config.cognitoEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1",                 forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.\(target)", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("No HTTP response")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if http.statusCode != 200 {
            let message = json["message"] as? String ?? "Unknown error"
            if http.statusCode == 400,
               let code = json["__type"] as? String,
               code.contains("NotAuthorized") || code.contains("UserNotFound") {
                throw AuthError.invalidCredentials
            }
            throw AuthError.networkError(message)
        }
        return json
    }

    // MARK: - JWT expiry check
    private func isTokenExpired(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return true }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard
            let data    = Data(base64Encoded: base64),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp     = payload["exp"] as? TimeInterval
        else { return true }
        return Date().timeIntervalSince1970 > exp - 60
    }

    // MARK: - Keychain helpers
    private func saveToken(key: String, value: String) {
        let data  = Data(value.utf8)
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key, kSecValueData: data]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadToken(key: String) -> String? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                                      kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteToken(key: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]
        SecItemDelete(query as CFDictionary)
    }
}
