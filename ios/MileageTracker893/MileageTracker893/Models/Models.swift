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

    // Safe decoding — backend may omit defaulted fields
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId          = try c.decode(String.self, forKey: .userId)
        vehicleId       = try c.decode(String.self, forKey: .vehicleId)
        name            = try c.decodeIfPresent(String.self, forKey: .name)            ?? ""
        make            = try c.decodeIfPresent(String.self, forKey: .make)            ?? ""
        model           = try c.decodeIfPresent(String.self, forKey: .model)           ?? ""
        year            = try c.decodeIfPresent(Int.self,    forKey: .year)            ?? 0
        currentOdometer = try c.decodeIfPresent(Double.self, forKey: .currentOdometer) ?? 0
        createdAt       = try c.decodeIfPresent(String.self, forKey: .createdAt)       ?? ""
        updatedAt       = try c.decodeIfPresent(String.self, forKey: .updatedAt)       ?? ""
    }
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

    // Safe decoding — backend may omit optional/defaulted fields on older records
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId           = try c.decode(String.self, forKey: .userId)
        tripId           = try c.decode(String.self, forKey: .tripId)
        vehicleId        = try c.decodeIfPresent(String.self, forKey: .vehicleId)        ?? ""
        startOdometer    = try c.decodeIfPresent(Double.self, forKey: .startOdometer)    ?? 0
        endOdometer      = try c.decodeIfPresent(Double.self, forKey: .endOdometer)      ?? 0
        odometerDistance = try c.decodeIfPresent(Double.self, forKey: .odometerDistance) ?? 0
        gpsDistance      = try c.decodeIfPresent(Double.self, forKey: .gpsDistance)      ?? 0
        tripDate         = try c.decodeIfPresent(String.self, forKey: .tripDate)         ?? ""
        purpose          = try c.decodeIfPresent(String.self, forKey: .purpose)          ?? ""
        notes            = try c.decodeIfPresent(String.self, forKey: .notes)            ?? ""
        createdAt        = try c.decodeIfPresent(String.self, forKey: .createdAt)        ?? ""
        updatedAt        = try c.decodeIfPresent(String.self, forKey: .updatedAt)        ?? ""
    }
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

    // Safe decoding — backend omits nil fields entirely (DynamoDB undefined → missing from JSON)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId       = try c.decode(String.self, forKey: .userId)
        expenseId    = try c.decode(String.self, forKey: .expenseId)
        vehicleId    = try c.decodeIfPresent(String.self,          forKey: .vehicleId)
        tripId       = try c.decodeIfPresent(String.self,          forKey: .tripId)
        category     = try c.decodeIfPresent(ExpenseCategory.self, forKey: .category)   ?? .other
        amount       = try c.decodeIfPresent(Double.self,          forKey: .amount)      ?? 0
        expenseDate  = try c.decodeIfPresent(String.self,          forKey: .expenseDate) ?? ""
        merchant     = try c.decodeIfPresent(String.self,          forKey: .merchant)    ?? ""
        notes        = try c.decodeIfPresent(String.self,          forKey: .notes)       ?? ""
        receiptS3Key = try c.decodeIfPresent(String.self,          forKey: .receiptS3Key)
        ocrStatus    = try c.decodeIfPresent(OCRStatus.self,       forKey: .ocrStatus)   ?? .none
        ocrData      = try c.decodeIfPresent(OCRData.self,         forKey: .ocrData)
        createdAt    = try c.decodeIfPresent(String.self,          forKey: .createdAt)   ?? ""
        updatedAt    = try c.decodeIfPresent(String.self,          forKey: .updatedAt)   ?? ""
    }
}

// MARK: - Expense Category
enum ExpenseCategory: String, Codable, CaseIterable {
    case fuel          = "fuel"
    case maintenance   = "maintenance"
    case insurance     = "insurance"
    case parking       = "parking"
    case tolls         = "tolls"
    case meals         = "meals"
    case travel        = "travel"
    case lodging       = "lodging"
    case groceries     = "groceries"
    case homeSupplies  = "home_supplies"
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total     = try c.decodeIfPresent(String.self,     forKey: .total)
        date      = try c.decodeIfPresent(String.self,     forKey: .date)
        merchant  = try c.decodeIfPresent(String.self,     forKey: .merchant)
        lineItems = try c.decodeIfPresent([LineItem].self,       forKey: .lineItems) ?? []
        rawFields = try c.decodeIfPresent([String: String].self, forKey: .rawFields) ?? [:]
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
