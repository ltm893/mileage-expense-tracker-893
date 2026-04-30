// Models.swift
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
    var odometerDistance: Double
    var gpsDistance:      Double
    var tripDate:         String
    var purpose:          String
    var notes:            String
    let createdAt:        String
    var updatedAt:        String

    var id: String { tripId }

    var distance: Double {
        odometerDistance > 0 ? odometerDistance : gpsDistance
    }
    var distanceFormatted: String { String(format: "%.1f mi", distance) }
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
    var vehicleId:    String?
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
    var isVehicleExpense: Bool { vehicleId != nil }
}

// MARK: - Expense Category
enum ExpenseCategory: String, Codable, CaseIterable {

    // Vehicle expenses
    case fuel          = "fuel"
    case maintenance   = "maintenance"
    case insurance     = "insurance"
    case parking       = "parking"
    case tolls         = "tolls"

    // General expenses
    case meals         = "meals"
    case travel        = "travel"
    case lodging       = "lodging"
    case groceries     = "groceries"      // was "supplies"
    case homeSupplies  = "home_supplies"  // new
    case utilities     = "utilities"
    case entertainment = "entertainment"
    case medical       = "medical"
    case other         = "other"

    var displayName: String {
        switch self {
        case .fuel:          return "Fuel"
        case .maintenance:   return "Maintenance"
        case .insurance:     return "Insurance"
        case .parking:       return "Parking"
        case .tolls:         return "Tolls"
        case .meals:         return "Meals"
        case .travel:        return "Travel"
        case .lodging:       return "Lodging"
        case .groceries:     return "Groceries"
        case .homeSupplies:  return "Home Supplies"
        case .utilities:     return "Utilities"
        case .entertainment: return "Entertainment"
        case .medical:       return "Medical"
        case .other:         return "Other"
        }
    }

    var icon: String {
        switch self {
        case .fuel:          return "fuelpump.fill"
        case .maintenance:   return "wrench.and.screwdriver.fill"
        case .insurance:     return "shield.fill"
        case .parking:       return "p.circle.fill"
        case .tolls:         return "road.lanes"
        case .meals:         return "fork.knife"
        case .travel:        return "airplane"
        case .lodging:       return "bed.double.fill"
        case .groceries:     return "basket.fill"
        case .homeSupplies:  return "house.fill"
        case .utilities:     return "bolt.fill"
        case .entertainment: return "ticket.fill"
        case .medical:       return "cross.case.fill"
        case .other:         return "ellipsis.circle.fill"
        }
    }

    static var vehicleCategories: [ExpenseCategory] {
        [.fuel, .maintenance, .insurance, .parking, .tolls]
    }

    static var generalCategories: [ExpenseCategory] {
        [.meals, .groceries, .homeSupplies, .travel, .lodging,
         .utilities, .entertainment, .medical, .other]
    }
}

// MARK: - OCR Status
enum OCRStatus: String, Codable {
    case none     = "none"
    case pending  = "pending"
    case complete = "complete"
    case failed   = "failed"
}

// MARK: - OCR Data
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
    let vehicleId:   String?
    let tripId:      String?
    let category:    String
    let amount:      Double
    let expenseDate: String
    let merchant:    String
    let notes:       String
}

struct UpdateExpenseRequest: Encodable {
    let vehicleId:    String?
    let tripId:       String?
    let category:     String
    let amount:       Double
    let expenseDate:  String
    let merchant:     String
    let notes:        String
    let receiptS3Key: String?
}

struct DeleteResponse: Decodable { let deleted: String }
