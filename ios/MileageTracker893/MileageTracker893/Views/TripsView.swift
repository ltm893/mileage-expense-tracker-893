// TripsView.swift
// One unified trip flow: GPS tracks automatically while user logs odometer readings.
// Both odometerDistance and gpsDistance are stored in DynamoDB on every trip.

import SwiftUI
import Combine
import CoreLocation

// MARK: - ViewModel
@MainActor
final class TripsViewModel: ObservableObject {
    @Published var trips:        [Trip]    = []
    @Published var vehicles:     [Vehicle] = []
    @Published var isLoading:    Bool      = false
    @Published var errorMessage: String?   = nil

    private let api = NetworkService.shared

    func load() async {
        isLoading = true; errorMessage = nil
        do {
            async let t: [Trip]    = api.get("trips")
            async let v: [Vehicle] = api.get("vehicles")
            (trips, vehicles) = try await (t, v)
            trips.sort { $0.tripDate > $1.tripDate }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func delete(_ trip: Trip) async {
        do {
            let _: DeleteResponse = try await api.delete("trips/\(trip.tripId)")
            trips.removeAll { $0.tripId == trip.tripId }
        } catch { errorMessage = error.localizedDescription }
    }

    func vehicleName(for id: String) -> String {
        vehicles.first { $0.vehicleId == id }?.name ?? "Unknown Vehicle"
    }
}

// MARK: - TripsView
struct TripsView: View {
    @StateObject private var vm      = TripsViewModel()
    @State private var showNewTrip   = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.trips.isEmpty {
                    ProgressView("Loading trips…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.trips.isEmpty {
                    ContentUnavailableView("No Trips", systemImage: "map.fill",
                        description: Text("Tap + to log your first trip."))
                } else {
                    List {
                        ForEach(vm.trips) { trip in
                            TripRow(trip: trip,
                                    vehicleName: vm.vehicleName(for: trip.vehicleId))
                        }
                        .onDelete { indexSet in
                            Task { for i in indexSet { await vm.delete(vm.trips[i]) } }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNewTrip = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNewTrip) {
                NewTripView(vehicles: vm.vehicles) { await vm.load() }
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: { Text(vm.errorMessage ?? "") })
            .task { await vm.load() }
            .background(AppColors.background)
        }
    }
}

// MARK: - Trip row
struct TripRow: View {
    let trip:        Trip
    let vehicleName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.tripDate)
                    .font(.headline).foregroundStyle(AppColors.primary)
                Spacer()
                Text(trip.distanceFormatted)
                    .font(.headline).foregroundStyle(AppColors.accent)
            }

            HStack(spacing: 6) {
                // GPS badge
                if trip.wasGPSTracked {
                    Label("GPS", systemImage: "location.fill")
                        .font(.caption2).foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(AppColors.accent.opacity(0.12))
                        .cornerRadius(4)
                }
                Text(vehicleName).font(.subheadline).foregroundStyle(.secondary)
            }

            // Show both measurements when available
            if let detail = trip.distanceDetail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }

            if !trip.purpose.isEmpty {
                Text(trip.purpose).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Trip (unified odometer + GPS)
// Flow:
//   Step 1 — Setup:   pick vehicle, enter start odometer (required), purpose
//   Step 2 — Active:  GPS tracks live distance while driving
//   Step 3 — End:     enter end odometer, review both distances, save
struct NewTripView: View {
    let vehicles: [Vehicle]
    var onSaved:  () async -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var gps = LocationManager()

    // Step 1 state
    @State private var selectedVehicleId = ""
    @State private var startOdometer     = ""
    @State private var purpose           = ""

    // Step 3 state
    @State private var endOdometer       = ""
    @State private var isSaving          = false
    @State private var errorMessage:       String?

    // Steps: 1 = setup, 2 = active trip, 3 = end/save
    @State private var step = 1

    private let api = NetworkService.shared
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var odometerDistance: Double {
        max(0, (Double(endOdometer) ?? 0) - (Double(startOdometer) ?? 0))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case 1: setupView
                case 2: activeView
                case 3: endView
                default: EmptyView()
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        gps.stopTrip()
                        dismiss()
                    }
                }
                if step == 1 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") { startTrip() }
                            .fontWeight(.semibold)
                            .disabled(!canStart)
                    }
                }
                if step == 3 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(isSaving || endOdometer.isEmpty)
                    }
                }
            }
            .onAppear {
                if selectedVehicleId.isEmpty, let first = vehicles.first {
                    selectedVehicleId = first.vehicleId
                }
                if gps.authorizationStatus == .notDetermined {
                    gps.requestPermission()
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case 1: return "New Trip"
        case 2: return "Trip in Progress"
        case 3: return "End Trip"
        default: return ""
        }
    }

    private var canStart: Bool {
        !selectedVehicleId.isEmpty && !startOdometer.isEmpty && gps.canTrack
    }

    // ── Step 1: Setup form ────────────────────────────────────────────────────
    private var setupView: some View {
        Form {
            Section("Vehicle") {
                if vehicles.isEmpty {
                    Text("Add a vehicle first.").foregroundStyle(.secondary)
                } else {
                    Picker("Vehicle", selection: $selectedVehicleId) {
                        ForEach(vehicles) { v in Text(v.name).tag(v.vehicleId) }
                    }
                }
            }

            Section("Start Odometer") {
                HStack {
                    TextField("Current odometer reading", text: $startOdometer)
                        .keyboardType(.decimalPad)
                    Text("mi").foregroundStyle(.secondary)
                }
            }

            Section("Purpose (optional)") {
                TextField("e.g. Client visit, commute", text: $purpose)
            }

            if !gps.canTrack {
                Section {
                    Button("Allow Location Access") { gps.requestPermission() }
                        .foregroundStyle(AppColors.accent)
                    Text("GPS tracking requires location access.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let error = gps.errorMessage {
                Section { Text(error).foregroundStyle(AppColors.destructive).font(.caption) }
            }
        }
    }

    // ── Step 2: Active trip display ───────────────────────────────────────────
    private var activeView: some View {
        VStack(spacing: 32) {
            Spacer()

            // GPS distance — primary live display
            VStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColors.accent)
                    .symbolEffect(.pulse)

                Text(String(format: "%.2f", gps.distanceMiles))
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primary)

                Text("GPS miles")
                    .font(.title3).foregroundStyle(.secondary)
            }

            // Elapsed time
            Text(gps.elapsedFormatted)
                .font(.title2.monospacedDigit())
                .foregroundStyle(.secondary)

            // Start odometer reminder
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.needle")
                Text("Started at \(startOdometer) mi")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()

            // End trip button
            Button {
                gps.stopTrip()
                step = 3
            } label: {
                Label("End Trip", systemImage: "stop.circle.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppColors.destructive)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // ── Step 3: End trip / review + save ─────────────────────────────────────
    private var endView: some View {
        Form {
            // Summary of GPS measurement
            Section("GPS Result") {
                LabeledContent("Distance",
                    value: String(format: "%.2f mi", gps.distanceMiles))
                LabeledContent("Duration", value: gps.elapsedFormatted)
            }

            // Odometer end reading
            Section("End Odometer") {
                HStack {
                    TextField("Current odometer reading", text: $endOdometer)
                        .keyboardType(.decimalPad)
                    Text("mi").foregroundStyle(.secondary)
                }
                if odometerDistance > 0 {
                    LabeledContent("Odometer distance",
                        value: String(format: "%.1f mi", odometerDistance))
                }
            }

            // Comparison when both are available
            if odometerDistance > 0 && gps.distanceMiles > 0 {
                Section("Comparison") {
                    LabeledContent("GPS",      value: String(format: "%.2f mi", gps.distanceMiles))
                    LabeledContent("Odometer", value: String(format: "%.1f mi", odometerDistance))
                    let diff = abs(gps.distanceMiles - odometerDistance)
                    LabeledContent("Difference", value: String(format: "%.2f mi", diff))
                        .foregroundStyle(diff > 2 ? .orange : .secondary)
                }
            }

            Section("Details") {
                TextField("Purpose (optional)", text: $purpose)
            }

            if let error = errorMessage {
                Section { Text(error).foregroundStyle(AppColors.destructive).font(.caption) }
            }
        }
    }

    // MARK: - Actions
    private func startTrip() {
        gps.startTrip()
        step = 2
    }

    private func save() async {
        isSaving = true; errorMessage = nil
        let startOdo = Double(startOdometer) ?? 0
        let endOdo   = Double(endOdometer)   ?? 0
        let odoDistance = max(0, endOdo - startOdo)

        do {
            let body = CreateTripRequest(
                vehicleId:        selectedVehicleId,
                startOdometer:    startOdo,
                endOdometer:      endOdo,
                odometerDistance: odoDistance,
                gpsDistance:      gps.distanceMiles,
                tripDate:         Self.df.string(from: Date()),
                purpose:          purpose,
                notes:            ""
            )
            let _: Trip = try await api.post("trips", body: body)
            await onSaved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
        isSaving = false
    }
}
