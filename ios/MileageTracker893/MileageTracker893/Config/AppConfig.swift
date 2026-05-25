// AppConfig.swift
// Loads met_outputs.json at startup — zero hardcoded strings anywhere else in the app.
// To point the app at a different backend, swap the JSON file and redeploy.

import Foundation

struct AppConfig {

    static let shared = AppConfig()

    // MARK: - API
    let apiBaseURL:     URL
    let awsRegion:      String

    // MARK: - Auth (Cognito)
    let userPoolId:     String
    let appClientId:    String
    let identityPoolId: String

    // MARK: - Storage
    let receiptsBucket: String

    // MARK: - Init — loads met_outputs.json from the app bundle
    private init() {
        guard
            let url  = Bundle.main.url(forResource: "met_outputs", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            fatalError("met_outputs.json not found in app bundle — add it to the Xcode target")
        }

        let api     = json["api"]     as? [String: Any] ?? [:]
        let auth    = json["auth"]    as? [String: Any] ?? [:]
        let storage = json["storage"] as? [String: Any] ?? [:]

        guard
            let baseURLString = api["base_url"] as? String,
            let baseURL       = URL(string: baseURLString)
        else {
            fatalError("met_outputs.json is missing api.base_url")
        }

        self.apiBaseURL     = baseURL
        self.awsRegion      = api["aws_region"]           as? String ?? "us-east-1"
        self.userPoolId     = auth["user_pool_id"]        as? String ?? ""
        self.appClientId    = auth["user_pool_client_id"] as? String ?? ""
        self.identityPoolId = auth["identity_pool_id"]    as? String ?? ""
        self.receiptsBucket = storage["receipts_bucket"]  as? String ?? ""
    }

    // Cognito endpoint — derived from region, never hardcoded
    var cognitoEndpoint: URL {
        URL(string: "https://cognito-idp.\(awsRegion).amazonaws.com/")!
    }
}
