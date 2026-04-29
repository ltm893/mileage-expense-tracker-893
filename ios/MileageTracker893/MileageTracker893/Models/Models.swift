// Models.swift
// All Codable data models — match DynamoDB attribute names exactly.
// No AWS types, no SDK imports — plain Swift structs.

import Foundation

// MARK: - Vehicle
struct Vehicle: Codable, Identifiable {
    let userId:          String
    let vehicleId:       String
    var name:            String
    var make:            String
    var model:           String
    var year:            Int
    var currentOdometer: Double
    let createdAt:       String
    var updatedAt:       String
    var id: String { vehicleId }
}

// MARK: - Trip
struct Trip: Codable, Identifiable {
    let userId:           String
    let tripId:           String
    var vehicleId:        String
    var startOdometer:    Double
    var endOdometer:      Double
    var odometerDistance: Double   // endOdometer - startOdometer
    var gpsDistance:      Double   // measured by CoreLocation
    var tripDate:         String   // "YYYY-MM-DD"
    var purpose:          String
    var notes:            String
    let createdAt:        String
    var updatedAt:        String

    var id: String { tripId }

    // Primary display distance — prefer odometer if both available
    var distance: Double {
        odometerDistance > 0 ? odometerDistance : gpsDistance
    }

    var distanceFormatted: String {
        String(format: "%.1f mi", distance)
    }

    // Shows both measurements when both were recorded
    var distanceDetail: String? {
        guard odometerDistance > 0 && gpsDistance > 0 else { return nil }
        return String(format: "Odometer: %.1f mi  ·  GPS: %.1f mi",
                      odometerDistance, gpsDistance)
    }

    var wasGPSTracked: Bool { gpsDistance > 0 }
}

// MARK: - Expense
struct Expense: Codable, Identifiable {
    let userId:       String
    let expenseId:    String
    var vehicleId:    String
    var tripId:       String?
    var category:     ExpenseCategory
    var amount:       Double
    var expenseDate:  String
    var merchant:     String
    var notes:        String
    var receiptS3Key: String?
    var ocrStatus:    OCRStatus
    var ocrData:      OCRData?
    let createdAt:    String
    var updatedAt:    String

    var id: String { expenseId }
    var amountFormatted: String { String(format: "$%.2f", amount) }
}

// MARK: - Expense Category
enum ExpenseCategory: String, Codable, CaseIterable {
    case fuel        = "fuel"
    case maintenance = "maintenance"
    case insurance   = "insurance"
    case parking     = "parking"
    case tolls       = "tolls"
    case other       = "other"

    var displayName: String {
        switch self {
        case .fuel:        return "Fuel"
        case .maintenance: return "Maintenance"
        case .insurance:   return "Insurance"
        case .parking:     return "Parking"
        case .tolls:       return "Tolls"
        case .other:       return "Other"
        }
    }

    var icon: String {
        switch self {
        case .fuel:        return "fuelpump.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .insurance:   return "shield.fill"
        case .parking:     return "p.circle.fill"
        case .tolls:       return "road.lanes"
        case .other:       return "ellipsis.circle.fill"
        }
    }
}

// MARK: - OCR Status
enum OCRStatus: String, Codable {
    case none     = "none"
    case pending  = "pending"
    case complete = "complete"
    case failed   = "failed"
}

// MARK: - OCR Data (from Textract)
struct OCRData: Codable {
    var total:     String?
    var date:      String?
    var merchant:  String?
    var lineItems: [LineItem]
    var rawFields: [String: String]

    struct LineItem: Codable {
        var description: String
        var amount:      String
    }
}

// MARK: - API Request bodies
struct CreateVehicleRequest: Encodable {
    let name: String; let make: String; let model: String
    let year: Int;    let currentOdometer: Double
}

struct UpdateVehicleRequest: Encodable {
    let name: String; let make: String; let model: String
    let year: Int;    let currentOdometer: Double
}

struct CreateTripRequest: Encodable {
    let vehicleId:        String
    let startOdometer:    Double
    let endOdometer:      Double
    let odometerDistance: Double
    let gpsDistance:      Double
    let tripDate:         String
    let purpose:          String
    let notes:            String
}

struct UpdateTripRequest: Encodable {
    let vehicleId:        String
    let startOdometer:    Double
    let endOdometer:      Double
    let odometerDistance: Double
    let gpsDistance:      Double
    let tripDate:         String
    let purpose:          String
    let notes:            String
}

struct CreateExpenseRequest: Encodable {
    let vehicleId: String; let tripId: String?; let category: String
    let amount: Double;    let expenseDate: String
    let merchant: String;  let notes: String
}

struct UpdateExpenseRequest: Encodable {
    let vehicleId: String;  let tripId: String?;      let category: String
    let amount: Double;     let expenseDate: String
    let merchant: String;   let notes: String;        let receiptS3Key: String?
}

struct DeleteResponse: Decodable { let deleted: String }
