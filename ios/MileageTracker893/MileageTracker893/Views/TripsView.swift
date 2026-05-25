// TripsView.swift
import SwiftUI
import Combine
import CoreLocation

// MARK: - Tracking mode

enum TrackingMode: String, CaseIterable, Identifiable {
    case gps      = "GPS"
    case odometer = "Odometer"
    case both     = "Both"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gps:      return "location.fill"
        case .odometer: return "gauge.with.needle"
        case .both:     return "arrow.triangle.merge"
        }
    }

    var description: String {
        switch self {
        case .gps:      return "Track live with location"
        case .odometer: return "Enter start & end readings"
        case .both:     return "GPS tracking + odometer"
        }
    }

    var needsGPS: Bool      { self == .gps || self == .both }
    var needsOdometer: Bool { self == .odometer || self == .both }
}

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
    @StateObject private var vm       = TripsViewModel()
    @State private var showNewTrip    = false
    @State private var selectedTrip:  Trip? = nil   // drives detail sheet

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
                            TripRow(trip: trip)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedTrip = trip }
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
            .sheet(item: $selectedTrip) { trip in
                TripDetailView(
                    trip:        trip,
                    vehicles:    vm.vehicles,
                    vehicleName: vm.vehicleName(for: trip.vehicleId),
                    onUpdated:   { await vm.load() }
                )
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: { Text(vm.errorMessage ?? "") })
            .task { await vm.load() }
        }
    }
}

// MARK: - Trip row (compact: date, miles, purpose if set)

struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.tripDate)
                    .font(.headline)
                    .foregroundStyle(AppColors.primary)
                Spacer()
                Text(trip.distanceFormatted)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppColors.accent)
            }
            if !trip.purpose.isEmpty {
                Text(trip.purpose)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Trip Detail sheet (read + edit)

struct TripDetailView: View {
    let trip:        Trip
    let vehicles:    [Vehicle]
    let vehicleName: String
    var onUpdated:   () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing    = false
    @State private var isSaving     = false
    @State private var showError    = false
    @State private var errorMessage = ""

    // Edit state
    @State private var selectedVehicleId = ""
    @State private var tripDate          = Date()
    @State private var startOdometer     = ""
    @State private var endOdometer       = ""
    @State private var odometerDistance  = ""
    @State private var gpsDistance       = ""
    @State private var purpose           = ""
    @State private var notes             = ""

    private let api = NetworkService.shared
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var computedOdoDistance: Double {
        let start = Double(startOdometer) ?? 0
        let end   = Double(endOdometer)   ?? 0
        return end > start ? end - start : (Double(odometerDistance) ?? 0)
    }

    private var canSave: Bool { !isSaving && !selectedVehicleId.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if isEditing { editSections } else { readSections }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle(isEditing ? "Edit Trip" : trip.tripDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .tint(AppColors.accent)
                            .disabled(!canSave)
                    } else {
                        Button("Edit") { isEditing = true }
                            .tint(AppColors.accent)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if isEditing {
                        Button("Cancel") { resetEditState(); isEditing = false }
                            .tint(AppColors.secondaryText)
                    } else {
                        Button("Done") { dismiss() }
                            .tint(AppColors.secondaryText)
                    }
                }
            }
            .alert("Save Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
            .onAppear { resetEditState() }
        }
    }

    // MARK: - Read-only sections

    private var readSections: some View {
        Group {
            Section("Trip") {
                LabeledContent("Date",     value: trip.tripDate)
                LabeledContent("Distance", value: trip.distanceFormatted)
                LabeledContent("Vehicle",  value: vehicleName)
                if !trip.purpose.isEmpty {
                    LabeledContent("Purpose", value: trip.purpose)
                }
                if !trip.notes.isEmpty {
                    LabeledContent("Notes", value: trip.notes)
                }
            }

            if trip.odometerDistance > 0 || trip.gpsDistance > 0 {
                Section("Distance Breakdown") {
                    if trip.odometerDistance > 0 {
                        LabeledContent("Odometer") {
                            Text(String(format: "%.1f mi", trip.odometerDistance))
                                .foregroundStyle(AppColors.primary)
                        }
                    }
                    if trip.gpsDistance > 0 {
                        LabeledContent("GPS") {
                            Text(String(format: "%.2f mi", trip.gpsDistance))
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    if trip.startOdometer > 0 {
                        LabeledContent("Start Odometer") {
                            Text(String(format: "%.1f mi", trip.startOdometer))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    if trip.endOdometer > 0 {
                        LabeledContent("End Odometer") {
                            Text(String(format: "%.1f mi", trip.endOdometer))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Edit sections

    private var editSections: some View {
        Group {
            Section("Trip") {
                DatePicker("Date", selection: $tripDate, displayedComponents: .date)
                    .tint(AppColors.accent)
                if !vehicles.isEmpty {
                    Picker("Vehicle", selection: $selectedVehicleId) {
                        ForEach(vehicles) { v in Text(v.name).tag(v.vehicleId) }
                    }
                    .tint(AppColors.accent)
                }
                TextField("Purpose (optional)", text: $purpose)
                TextField("Notes (optional)",   text: $notes)
            }

            Section("Odometer") {
                HStack {
                    Text("Start")
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(width: 50, alignment: .leading)
                    TextField("Reading", text: $startOdometer)
                        .keyboardType(.decimalPad)
                    Text("mi").foregroundStyle(AppColors.secondaryText)
                }
                HStack {
                    Text("End")
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(width: 50, alignment: .leading)
                    TextField("Reading", text: $endOdometer)
                        .keyboardType(.decimalPad)
                    Text("mi").foregroundStyle(AppColors.secondaryText)
                }
                if (Double(startOdometer) ?? 0) == 0 && (Double(endOdometer) ?? 0) == 0 {
                    HStack {
                        Text("Distance")
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(width: 70, alignment: .leading)
                        TextField("Miles", text: $odometerDistance)
                            .keyboardType(.decimalPad)
                        Text("mi").foregroundStyle(AppColors.secondaryText)
                    }
                } else if computedOdoDistance > 0 {
                    LabeledContent("Distance") {
                        Text(String(format: "%.1f mi", computedOdoDistance))
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }

            Section("GPS") {
                HStack {
                    TextField("GPS distance", text: $gpsDistance)
                        .keyboardType(.decimalPad)
                    Text("mi").foregroundStyle(AppColors.secondaryText)
                }
            }

            if isSaving {
                Section {
                    HStack {
                        ProgressView().tint(AppColors.accent)
                        Text("Saving…").foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func resetEditState() {
        selectedVehicleId = trip.vehicleId
        purpose           = trip.purpose
        notes             = trip.notes
        startOdometer     = trip.startOdometer    > 0 ? String(format: "%.1f", trip.startOdometer)    : ""
        endOdometer       = trip.endOdometer      > 0 ? String(format: "%.1f", trip.endOdometer)      : ""
        odometerDistance  = trip.odometerDistance > 0 ? String(format: "%.1f", trip.odometerDistance) : ""
        gpsDistance       = trip.gpsDistance      > 0 ? String(format: "%.2f", trip.gpsDistance)      : ""
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        tripDate = f.date(from: trip.tripDate) ?? Date()
    }

    private func save() async {
        isSaving = true
        let startOdo = Double(startOdometer) ?? 0
        let endOdo   = Double(endOdometer)   ?? 0

        // Use exactly what the user typed — empty field means zero, not "keep old value".
        // This allows clearing odometer fields when switching to GPS-only.
        let odoDistSave: Double = {
            if endOdo > startOdo && startOdo > 0 { return endOdo - startOdo }
            return Double(odometerDistance) ?? 0
        }()
        let gpsDist = Double(gpsDistance) ?? 0
        do {
            let body = UpdateTripRequest(
                vehicleId:        selectedVehicleId,
                startOdometer:    startOdo,
                endOdometer:      endOdo,
                odometerDistance: odoDistSave,
                gpsDistance:      gpsDist,
                tripDate:         Self.df.string(from: tripDate),
                purpose:          purpose,
                notes:            notes
            )
            let _: Trip = try await api.put("trips/\(trip.tripId)", body: body)
            await onUpdated()
            isEditing = false
        } catch {
            errorMessage = error.localizedDescription
            showError    = true
        }
        isSaving = false
    }
}

// MARK: - New Trip

struct NewTripView: View {
    let vehicles: [Vehicle]
    var onSaved:  () async -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var gps = LocationManager()

    @State private var trackingMode      = TrackingMode.both
    @State private var selectedVehicleId = ""
    @State private var startOdometer     = ""
    @State private var endOdometer       = ""
    @State private var purpose           = ""
    @State private var manualDate        = Date()
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

    private var canSave: Bool {
        if isSaving { return false }
        if trackingMode.needsOdometer { return !endOdometer.isEmpty }
        return true
    }

    private var canStart: Bool {
        guard !selectedVehicleId.isEmpty else { return false }
        if trackingMode.needsOdometer && startOdometer.isEmpty { return false }
        if trackingMode.needsGPS && !gps.canTrack              { return false }
        return true
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
                        Button(trackingMode.needsGPS ? "Start" : "Next") { advance() }
                            .fontWeight(.semibold).tint(AppColors.accent)
                            .disabled(!canStart)
                    }
                }
                if step == 3 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold).tint(AppColors.accent)
                            .disabled(!canSave)
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

    private func advance() {
        if trackingMode.needsGPS { gps.startTrip(); step = 2 }
        else                     { step = 3 }
    }

    // ── Step 1: Setup ──────────────────────────────────────────────────────────

    private var setupView: some View {
        Form {
            Section {
                ForEach(TrackingMode.allCases) { mode in
                    Button {
                        trackingMode = mode
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(trackingMode == mode ? AppColors.accent : AppColors.accentTint)
                                    .frame(width: 32, height: 32)
                                Image(systemName: mode.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(trackingMode == mode ? .white : AppColors.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(AppColors.primary)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            Spacer()
                            if trackingMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text("Tracking Method") }

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

            if trackingMode.needsOdometer {
                Section("Start Odometer") {
                    HStack {
                        TextField("Current reading", text: $startOdometer)
                            .keyboardType(.decimalPad)
                        Text("mi").foregroundStyle(AppColors.secondaryText)
                    }
                }
            }

            Section("Purpose (optional)") {
                TextField("e.g. Client visit", text: $purpose)
            }

            if trackingMode.needsGPS && !gps.canTrack {
                Section {
                    Button("Allow Location Access") { gps.requestPermission() }
                        .foregroundStyle(AppColors.accent)
                } footer: {
                    Text("Location access is required for GPS tracking.")
                        .font(.caption)
                }
            }

            if trackingMode == .odometer {
                Section("Trip Date") {
                    DatePicker("Date", selection: $manualDate, displayedComponents: .date)
                        .tint(AppColors.accent)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // ── Step 2: Active GPS tracking ───────────────────────────────────────────

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
            if trackingMode.needsOdometer {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle")
                    Text("Started at \(startOdometer) mi")
                }
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
            }
            Spacer()
            Button {
                gps.stopTrip(); step = 3
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
            if trackingMode.needsGPS {
                Section("GPS Result") {
                    LabeledContent("Distance") {
                        Text(String(format: "%.2f mi", gps.distanceMiles))
                            .foregroundStyle(AppColors.accent).fontWeight(.semibold)
                    }
                    LabeledContent("Duration") {
                        Text(gps.elapsedFormatted).foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
            if trackingMode.needsOdometer {
                Section("End Odometer") {
                    HStack {
                        TextField("Current reading", text: $endOdometer)
                            .keyboardType(.decimalPad)
                        Text("mi").foregroundStyle(AppColors.secondaryText)
                    }
                    if odometerDistance > 0 {
                        LabeledContent("Odometer distance") {
                            Text(String(format: "%.1f mi", odometerDistance))
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                }
            }
            if trackingMode == .both && odometerDistance > 0 && gps.distanceMiles > 0 {
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
            if trackingMode == .odometer {
                Section("Trip Date") {
                    DatePicker("Date", selection: $manualDate, displayedComponents: .date)
                        .tint(AppColors.accent)
                }
            }
            Section("Details") {
                TextField("Purpose (optional)", text: $purpose)
            }
            if isSaving {
                Section {
                    HStack {
                        ProgressView().tint(AppColors.accent)
                        Text("Saving…").foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        let startOdo    = Double(startOdometer) ?? 0
        let endOdo      = Double(endOdometer)   ?? 0
        let odoDistance = trackingMode.needsOdometer ? max(0, endOdo - startOdo) : 0
        let gpsDist     = trackingMode.needsGPS      ? gps.distanceMiles         : 0
        let tripDate    = trackingMode == .odometer
                            ? Self.df.string(from: manualDate)
                            : Self.df.string(from: Date())
        do {
            let body = CreateTripRequest(
                vehicleId:        selectedVehicleId,
                startOdometer:    startOdo,
                endOdometer:      endOdo,
                odometerDistance: odoDistance,
                gpsDistance:      gpsDist,
                tripDate:         tripDate,
                purpose:          purpose,
                notes:            ""
            )
            let _: Trip = try await api.post("trips", body: body)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError    = true
        }
        isSaving = false
    }
}
