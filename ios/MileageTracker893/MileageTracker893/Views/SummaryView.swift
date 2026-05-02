// SummaryView.swift
// Dashboard summary of mileage + expenses with combined CSV export.
import Combine
import SwiftUI

// MARK: - Date range filter

enum DateRangeFilter: String, CaseIterable, Identifiable {
    case thisMonth  = "This Month"
    case last30     = "Last 30 Days"
    case last90     = "Last 90 Days"
    case thisYear   = "This Year"
    case allTime    = "All Time"

    var id: String { rawValue }

    func startDate() -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .thisMonth:  return cal.date(from: cal.dateComponents([.year, .month], from: now))
        case .last30:     return cal.date(byAdding: .day, value: -30, to: now)
        case .last90:     return cal.date(byAdding: .day, value: -90, to: now)
        case .thisYear:   return cal.date(from: cal.dateComponents([.year], from: now))
        case .allTime:    return nil
        }
    }
}

// MARK: - ViewModel

@MainActor
final class SummaryViewModel: ObservableObject {
    @Published var trips:        [Trip]    = []
    @Published var expenses:     [Expense] = []
    @Published var vehicles:     [Vehicle] = []
    @Published var isLoading:    Bool      = false
    @Published var errorMessage: String?   = nil
    @Published var filter:       DateRangeFilter = .allTime

    private let api = NetworkService.shared

    private static let isoDF: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func load() async {
        isLoading = true; errorMessage = nil
        do {
            async let t: [Trip]    = api.get("trips")
            async let e: [Expense] = api.get("expenses")
            async let v: [Vehicle] = api.get("vehicles")
            (trips, expenses, vehicles) = try await (t, e, v)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    // MARK: - Filtered data

    private func parse(_ dateString: String) -> Date? {
        Self.isoDF.date(from: dateString)
    }

    var filteredTrips: [Trip] {
        guard let start = filter.startDate() else { return trips }
        return trips.filter { parse($0.tripDate).map { $0 >= start } ?? true }
    }

    var filteredExpenses: [Expense] {
        guard let start = filter.startDate() else { return expenses }
        return expenses.filter { parse($0.expenseDate).map { $0 >= start } ?? true }
    }

    // MARK: - Mileage stats

    var totalMiles: Double      { filteredTrips.reduce(0) { $0 + $1.distance } }
    var totalTrips: Int         { filteredTrips.count }
    var avgMilesPerTrip: Double { totalTrips > 0 ? totalMiles / Double(totalTrips) : 0 }

    /// Miles grouped by vehicle
    var milesByVehicle: [(name: String, miles: Double)] {
        var map: [String: Double] = [:]
        for trip in filteredTrips {
            map[trip.vehicleId, default: 0] += trip.distance
        }
        return map.compactMap { vehicleId, miles in
            guard let vehicle = vehicles.first(where: { $0.vehicleId == vehicleId }) else { return nil }
            return (name: vehicle.name, miles: miles)
        }
        .sorted { $0.miles > $1.miles }
    }

    // MARK: - Expense stats

    var totalExpenses: Double   { filteredExpenses.reduce(0) { $0 + $1.amount } }
    var totalExpenseCount: Int  { filteredExpenses.count }

    /// Expenses by category, sorted descending
    var expensesByCategory: [(category: ExpenseCategory, total: Double, count: Int)] {
        var map: [ExpenseCategory: (Double, Int)] = [:]
        for exp in filteredExpenses {
            let (total, count) = map[exp.category, default: (0, 0)]
            map[exp.category] = (total + exp.amount, count + 1)
        }
        return map.map { cat, pair in
            (category: cat, total: pair.0, count: pair.1)
        }
        .sorted { $0.total > $1.total }
    }

    var vehicleExpenseTotal: Double {
        filteredExpenses.filter { $0.vehicleId != nil }.reduce(0) { $0 + $1.amount }
    }
    var generalExpenseTotal: Double {
        filteredExpenses.filter { $0.vehicleId == nil }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Vehicle name helper

    func vehicleName(for id: String?) -> String {
        guard let id else { return "General" }
        return vehicles.first { $0.vehicleId == id }?.name ?? "Unknown"
    }

    // MARK: - CSV builders

    func tripsCSV() -> String {
        let vehicleMap = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.vehicleId, $0.name) })
        let sorted     = filteredTrips.sorted { $0.tripDate > $1.tripDate }

        var csv = "Date,Vehicle,Distance (mi),GPS Distance (mi),Odometer Distance (mi),Purpose,Notes\n"
        for trip in sorted {
            let vName    = (vehicleMap[trip.vehicleId] ?? "Unknown").escapedCSV
            let distance = String(format: "%.2f", trip.distance)
            let gps      = String(format: "%.2f", trip.gpsDistance)
            let odo      = String(format: "%.2f", trip.odometerDistance)
            csv += "\(trip.tripDate),\(vName),\(distance),\(gps),\(odo),\(trip.purpose.escapedCSV),\(trip.notes.escapedCSV)\n"
        }
        return csv
    }

    func expensesCSV() -> String {
        let sorted = filteredExpenses.sorted { $0.expenseDate > $1.expenseDate }

        var csv = "Date,Category,Amount,Merchant,Vehicle,Notes\n"
        for exp in sorted {
            let vehicle = vehicleName(for: exp.vehicleId).escapedCSV
            csv += "\(exp.expenseDate),\(exp.category.displayName.escapedCSV),"
                 + "\(String(format: "%.2f", exp.amount)),"
                 + "\(exp.merchant.escapedCSV),\(vehicle),\(exp.notes.escapedCSV)\n"
        }
        return csv
    }

    func combinedCSV() -> String {
        """
        === MILEAGE SUMMARY (\(filter.rawValue)) ===
        Total Trips,\(totalTrips)
        Total Miles,\(String(format: "%.2f", totalMiles))
        Avg Miles per Trip,\(String(format: "%.2f", avgMilesPerTrip))

        === TRIPS ===
        \(tripsCSV())
        === EXPENSE SUMMARY (\(filter.rawValue)) ===
        Total Expenses,\(String(format: "%.2f", totalExpenses))
        Vehicle Expenses,\(String(format: "%.2f", vehicleExpenseTotal))
        General Expenses,\(String(format: "%.2f", generalExpenseTotal))

        === EXPENSES ===
        \(expensesCSV())
        """
    }
}

// MARK: - String CSV helper
private extension String {
    var escapedCSV: String {
        if contains(",") || contains("\"") || contains("\n") {
            return "\"" + replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return self
    }
}

// MARK: - SummaryView

struct SummaryView: View {
    @StateObject private var vm          = SummaryViewModel()
    @State private var exportURL:         URL?        = nil
    @State private var isExporting:       Bool        = false
    @State private var showShareSheet:    Bool        = false
    @State private var showExportPicker:  Bool        = false
    @State private var exportError:       String?     = nil
    @State private var showExportError:   Bool        = false

    enum ExportMode { case trips, expenses, combined }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading summary…")
                        .tint(AppColors.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            filterCard
                            mileageCard
                            expensesCard
                            exportCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                }
            }
            .background(AppColors.background)
            .navigationTitle("Summary")
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: { Text(exportError ?? "Unknown error") }
            .confirmationDialog("Export as CSV", isPresented: $showExportPicker, titleVisibility: .visible) {
                Button("Trips only")                   { Task { await doExport(.trips) } }
                Button("Expenses only")                { Task { await doExport(.expenses) } }
                Button("Combined (trips + expenses)")  { Task { await doExport(.combined) } }
                Button("Cancel", role: .cancel)        { }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL { ShareSheet(url: url) }
            }
            .task { await vm.load() }
        }
    }

    // MARK: - Filter card

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Date Range", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(AppColors.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DateRangeFilter.allCases) { range in
                        let selected = vm.filter == range
                        Button(range.rawValue) {
                            vm.filter = range
                        }
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(selected ? AppColors.accent : AppColors.background)
                        .foregroundStyle(selected ? .white : AppColors.secondaryText)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selected ? AppColors.accent : AppColors.accentTint, lineWidth: 1)
                        )
                        .animation(.easeInOut(duration: 0.15), value: vm.filter)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(14)
        .shadow(color: AppColors.shadowColor, radius: 6, y: 2)
    }

    // MARK: - Mileage card

    private var mileageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Mileage", systemImage: "car.fill")
                .font(.headline)
                .foregroundStyle(AppColors.primary)

            if vm.totalTrips == 0 {
                Text("No trips in this period.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
            } else {
                HStack(spacing: 12) {
                    StatPill(value: String(format: "%.1f", vm.totalMiles),
                             label: "Total Miles",
                             icon: "gauge.with.needle")
                    StatPill(value: "\(vm.totalTrips)",
                             label: "Trips",
                             icon: "map.fill")
                    StatPill(value: String(format: "%.1f", vm.avgMilesPerTrip),
                             label: "Avg mi/trip",
                             icon: "arrow.left.and.right")
                }

                if !vm.milesByVehicle.isEmpty {
                    Divider()
                    Text("By Vehicle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryText)

                    ForEach(vm.milesByVehicle, id: \.name) { item in
                        VehicleBar(
                            name:  item.name,
                            miles: item.miles,
                            total: vm.totalMiles
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(14)
        .shadow(color: AppColors.shadowColor, radius: 6, y: 2)
    }

    // MARK: - Expenses card

    private var expensesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Expenses", systemImage: "creditcard.fill")
                .font(.headline)
                .foregroundStyle(AppColors.primary)

            if vm.totalExpenseCount == 0 {
                Text("No expenses in this period.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
            } else {
                HStack(spacing: 12) {
                    StatPill(value: String(format: "$%.0f", vm.totalExpenses),
                             label: "Total",
                             icon: "dollarsign.circle.fill")
                    StatPill(value: String(format: "$%.0f", vm.vehicleExpenseTotal),
                             label: "Vehicle",
                             icon: "car.rear.fill")
                    StatPill(value: String(format: "$%.0f", vm.generalExpenseTotal),
                             label: "General",
                             icon: "bag.fill")
                }

                if !vm.expensesByCategory.isEmpty {
                    Divider()
                    Text("By Category")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryText)

                    ForEach(vm.expensesByCategory, id: \.category) { item in
                        CategoryRow(
                            category:   item.category,
                            total:      item.total,
                            count:      item.count,
                            grandTotal: vm.totalExpenses
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(14)
        .shadow(color: AppColors.shadowColor, radius: 6, y: 2)
    }

    // MARK: - Export card

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.headline)
                .foregroundStyle(AppColors.primary)

            Text("Exports trips and expenses for the selected period (\(vm.filter.rawValue)) as a CSV file.")
                .font(.caption)
                .foregroundStyle(AppColors.secondaryText)

            Button {
                showExportPicker = true
            } label: {
                HStack {
                    Spacer()
                    if isExporting {
                        ProgressView().tint(.white)
                        Text("Preparing…").fontWeight(.semibold)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export CSV").fontWeight(.semibold)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(AppColors.accent)
                .foregroundStyle(.white)
                .cornerRadius(10)
            }
            .disabled(isExporting)
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(14)
        .shadow(color: AppColors.shadowColor, radius: 6, y: 2)
    }

    // MARK: - Export action

    private func doExport(_ mode: ExportMode) async {
        isExporting = true
        do {
            if vm.trips.isEmpty && vm.expenses.isEmpty { await vm.load() }

            let csvString: String
            let fileName: String
            let today    = formattedToday()
            let period   = vm.filter.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")

            switch mode {
            case .trips:
                csvString = vm.tripsCSV()
                fileName  = "trips_\(period)_\(today).csv"
            case .expenses:
                csvString = vm.expensesCSV()
                fileName  = "expenses_\(period)_\(today).csv"
            case .combined:
                csvString = vm.combinedCSV()
                fileName  = "mileage_expenses_\(period)_\(today).csv"
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileName)
            try csvString.write(to: tempURL, atomically: true, encoding: .utf8)

            exportURL      = tempURL
            showShareSheet = true
        } catch {
            exportError     = error.localizedDescription
            showExportError = true
        }
        isExporting = false
    }

    private func formattedToday() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Sub-views

private struct StatPill: View {
    let value: String
    let label: String
    let icon:  String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppColors.accent)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(AppColors.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppColors.background)
        .cornerRadius(10)
    }
}

private struct VehicleBar: View {
    let name:  String
    let miles: Double
    let total: Double

    private var fraction: Double { total > 0 ? miles / total : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.primary)
                Spacer()
                Text(String(format: "%.1f mi", miles))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppColors.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.accentTint)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.accentLight)
                        .frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct CategoryRow: View {
    let category:   ExpenseCategory
    let total:      Double
    let count:      Int
    let grandTotal: Double

    private var fraction: Double { grandTotal > 0 ? total / grandTotal : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 16)
                Text(category.displayName)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.primary)
                Spacer()
                Text("\(count)×")
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                Text(String(format: "$%.2f", total))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppColors.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.accentTint)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.accentLight)
                        .frame(width: geo.size.width * fraction, height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}
