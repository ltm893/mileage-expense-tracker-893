// TripsView.swift
import SwiftUI
import Combine
import CoreLocation

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
    @StateObject private var vm    = TripsViewModel()
    @State private var showNewTrip = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.trips.isEmpty {
                    ProgressView("Loading trips…")
                        .tint(AppColors.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.trips.isEmpty {
                    ContentUnavailableView("No Trips", systemImage: "map.fill",
                        description: Text("Tap + to log your first trip."))
                } else {
                    List {
                        ForEach(vm.trips) { trip in
                            TripRow(trip: trip, vehicleName: vm.vehicleName(for: trip.vehicleId))
                        }
                        .onDelete { indexSet in
                            Task { for i in indexSet { await vm.delete(vm.trips[i]) } }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppColors.background)
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNewTrip = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .tint(AppColors.accent)
                }
            }
            .sheet(isPresented: $showNewTrip) {
                NewTripView(vehicles: vm.vehicles) { await vm.load() }
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: { Text(vm.errorMessage ?? "") })
            .task { await vm.load() }
        }
    }
}

// MARK: - Trip row
struct TripRow: View {
    let trip:        Trip
    let vehicleName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(trip.tripDate)
                    .font(.headline).foregroundStyle(AppColors.primary)
                Spacer()
                Text(trip.distanceFormatted)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppColors.accent)
            }

            HStack(spacing: 6) {
                if trip.wasGPSTracked {
                    HStack(spacing: 3) {
                        Image(systemName: "location.fill").font(.caption2)
                        Text("GPS")
                    }
                    .font(.caption2).foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(AppColors.accentTint)
                    .cornerRadius(4)
                }
                Text(vehicleName)
                    .font(.subheadline).foregroundStyle(AppColors.secondaryText)
            }

            if let detail = trip.distanceDetail {
                Text(detail)
                    .font(.caption).foregroundStyle(AppColors.secondaryText)
            }

            if !trip.purpose.isEmpty {
                Text(trip.purpose)
                    .font(.caption).foregroundStyle(AppColors.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Trip (unified GPS + odometer)
struct NewTripView: View {
    let vehicles: [Vehicle]
    var onSaved:  () async -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var gps = LocationManager()

    @State private var selectedVehicleId = ""
    @State private var startOdometer     = ""
    @State private var purpose           = ""
    @State private var endOdometer       = ""
    @State private var isSaving          = false
    @State private var showError         = false
    @State private var errorMessage      = ""
    @State private var step              = 1

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
            .background(AppColors.background)
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { gps.stopTrip(); dismiss() }
                        .tint(AppColors.secondaryText)
                }
                if step == 1 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") { startTrip() }
                            .fontWeight(.semibold).tint(AppColors.accent)
                            .disabled(!canStart)
                    }
                }
                if step == 3 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold).tint(AppColors.accent)
                            .disabled(isSaving || endOdometer.isEmpty)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
            .onAppear {
                if selectedVehicleId.isEmpty, let first = vehicles.first {
                    selectedVehicleId = first.vehicleId
                }
                if gps.authorizationStatus == .notDetermined { gps.requestPermission() }
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

    // ── Step 1: Setup ─────────────────────────────────────────────────────────
    private var setupView: some View {
        Form {
            Section("Vehicle") {
                if vehicles.isEmpty {
                    Text("Add a vehicle first.").foregroundStyle(AppColors.secondaryText)
                } else {
                    Picker("Vehicle", selection: $selectedVehicleId) {
                        ForEach(vehicles) { v in Text(v.name).tag(v.vehicleId) }
                    }
                    .tint(AppColors.accent)
                }
            }
            Section("Start Odometer") {
                HStack {
                    TextField("Current reading", text: $startOdometer).keyboardType(.decimalPad)
                    Text("mi").foregroundStyle(AppColors.secondaryText)
                }
            }
            Section("Purpose (optional)") {
                TextField("e.g. Client visit", text: $purpose)
            }
            if !gps.canTrack {
                Section {
                    Button("Allow Location Access") { gps.requestPermission() }
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // ── Step 2: Active tracking ───────────────────────────────────────────────
    private var activeView: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColors.accentTint)
                    .frame(width: 180, height: 180)
                Circle()
                    .strokeBorder(AppColors.accent, lineWidth: 3)
                    .frame(width: 180, height: 180)
                VStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.accent)
                        .symbolEffect(.pulse)
                    Text(String(format: "%.2f", gps.distanceMiles))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.primary)
                    Text("GPS miles")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            Text(gps.elapsedFormatted)
                .font(.title2.monospacedDigit())
                .foregroundStyle(AppColors.secondaryText)

            HStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                Text("Started at \(startOdometer) mi")
            }
            .font(.subheadline)
            .foregroundStyle(AppColors.secondaryText)

            Spacer()

            Button {
                gps.stopTrip()
                step = 3
            } label: {
                Label("End Trip", systemImage: "stop.circle.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity).padding()
                    .background(AppColors.destructive)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                    .shadow(color: AppColors.destructive.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // ── Step 3: End / save ────────────────────────────────────────────────────
    private var endView: some View {
        Form {
            Section("GPS Result") {
                LabeledContent("Distance") {
                    Text(String(format: "%.2f mi", gps.distanceMiles))
                        .foregroundStyle(AppColors.accent).fontWeight(.semibold)
                }
                LabeledContent("Duration") {
                    Text(gps.elapsedFormatted).foregroundStyle(AppColors.secondaryText)
                }
            }
            Section("End Odometer") {
                HStack {
                    TextField("Current reading", text: $endOdometer).keyboardType(.decimalPad)
                    Text("mi").foregroundStyle(AppColors.secondaryText)
                }
                if odometerDistance > 0 {
                    LabeledContent("Odometer distance") {
                        Text(String(format: "%.1f mi", odometerDistance))
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
            if odometerDistance > 0 && gps.distanceMiles > 0 {
                Section("Comparison") {
                    LabeledContent("GPS") {
                        Text(String(format: "%.2f mi", gps.distanceMiles))
                            .foregroundStyle(AppColors.accent)
                    }
                    LabeledContent("Odometer") {
                        Text(String(format: "%.1f mi", odometerDistance))
                            .foregroundStyle(AppColors.primary)
                    }
                    let diff = abs(gps.distanceMiles - odometerDistance)
                    LabeledContent("Difference") {
                        Text(String(format: "%.2f mi", diff))
                            .foregroundStyle(diff > 2 ? AppColors.warning : AppColors.secondaryText)
                    }
                }
            }
            Section("Details") {
                TextField("Purpose (optional)", text: $purpose)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func startTrip() { gps.startTrip(); step = 2 }

    private func save() async {
        isSaving = true
        let startOdo    = Double(startOdometer) ?? 0
        let endOdo      = Double(endOdometer)   ?? 0
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
            await onSaved(); dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSaving = false
    }
}
