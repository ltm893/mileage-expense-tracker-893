// VehiclesView.swift
import SwiftUI
import Combine

@MainActor
final class VehiclesViewModel: ObservableObject {
    @Published var vehicles:     [Vehicle] = []
    @Published var isLoading:    Bool      = false
    @Published var errorMessage: String?   = nil

    private let api = NetworkService.shared

    func load() async {
        isLoading = true; errorMessage = nil
        do { vehicles = try await api.get("vehicles") }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func delete(_ vehicle: Vehicle) async {
        do {
            let _: DeleteResponse = try await api.delete("vehicles/\(vehicle.vehicleId)")
            vehicles.removeAll { $0.vehicleId == vehicle.vehicleId }
        } catch { errorMessage = error.localizedDescription }
    }
}

struct VehiclesView: View {
    @StateObject private var vm = VehiclesViewModel()
    @State private var showAdd  = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.vehicles.isEmpty {
                    ProgressView("Loading vehicles…")
                        .tint(AppColors.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.vehicles.isEmpty {
                    ContentUnavailableView("No Vehicles", systemImage: "car.fill",
                        description: Text("Tap + to add your first vehicle."))
                } else {
                    List {
                        ForEach(vm.vehicles) { vehicle in
                            NavigationLink(destination: VehicleDetailView(
                                vehicle: vehicle,
                                onUpdated: { await vm.load() }
                            )) {
                                VehicleRow(vehicle: vehicle)
                            }
                        }
                        .onDelete { indexSet in
                            Task { for i in indexSet { await vm.delete(vm.vehicles[i]) } }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppColors.background)
            .navigationTitle("Vehicles")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .tint(AppColors.accent)
                }
            }
            .sheet(isPresented: $showAdd) { AddVehicleView { await vm.load() } }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: { Text(vm.errorMessage ?? "") })
            .task { await vm.load() }
        }
    }
}

// MARK: - Vehicle row
struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.accentTint)
                    .frame(width: 44, height: 44)
                Image(systemName: "car.fill")
                    .foregroundStyle(AppColors.accent)
                    .font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.name)
                    .font(.headline)
                    .foregroundStyle(AppColors.primary)
                Text("\(vehicle.year) \(vehicle.make) \(vehicle.model)")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
                Text(String(format: "%.0f mi", vehicle.currentOdometer))
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Vehicle
struct AddVehicleView: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name      = ""
    @State private var make      = ""
    @State private var model     = ""
    @State private var yearText  = String(Calendar.current.component(.year, from: Date()))
    @State private var odometer  = ""
    @State private var isSaving  = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let api = NetworkService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle Info") {
                    TextField("Nickname (e.g. My Truck)", text: $name)
                    TextField("Make (e.g. Ford)",         text: $make)
                    TextField("Model (e.g. F-150)",       text: $model)
                    // Year as plain text field — no Stepper, no comma formatting
                    HStack {
                        Text("Year")
                        Spacer()
                        TextField("e.g. 2022", text: $yearText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                Section("Odometer") {
                    HStack {
                        TextField("Current miles", text: $odometer).keyboardType(.decimalPad)
                        Text("mi").foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle("Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(AppColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave || isSaving)
                        .tint(AppColors.accent)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
        }
    }

    private var canSave: Bool { !name.isEmpty && !make.isEmpty && !model.isEmpty }

    private func save() async {
        isSaving = true
        do {
            let body = CreateVehicleRequest(
                name:            name,
                make:            make,
                model:           model,
                year:            Int(yearText) ?? 2024,
                currentOdometer: Double(odometer) ?? 0
            )
            let _: Vehicle = try await api.post("vehicles", body: body)
            await onSaved(); dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSaving = false
    }
}

// MARK: - Vehicle Detail
struct VehicleDetailView: View {
    let vehicle:   Vehicle
    var onUpdated: () async -> Void

    @State private var name      = ""
    @State private var make      = ""
    @State private var model     = ""
    @State private var yearText  = ""
    @State private var odometer  = ""
    @State private var isSaving  = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let api = NetworkService.shared

    var body: some View {
        Form {
            Section("Vehicle Info") {
                TextField("Nickname", text: $name)
                TextField("Make",     text: $make)
                TextField("Model",    text: $model)
                HStack {
                    Text("Year")
                    Spacer()
                    TextField("e.g. 2022", text: $yearText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
            Section("Odometer") {
                HStack {
                    TextField("Current miles", text: $odometer).keyboardType(.decimalPad)
                    Text("mi").foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(vehicle.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving)
                    .tint(AppColors.accent)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage) }
        .onAppear {
            name     = vehicle.name
            make     = vehicle.make
            model    = vehicle.model
            yearText = String(vehicle.year)
            odometer = String(format: "%.0f", vehicle.currentOdometer)
        }
    }

    private func save() async {
        isSaving = true
        do {
            let body = UpdateVehicleRequest(
                name:            name,
                make:            make,
                model:           model,
                year:            Int(yearText) ?? vehicle.year,
                currentOdometer: Double(odometer) ?? vehicle.currentOdometer
            )
            let _: Vehicle = try await api.put("vehicles/\(vehicle.vehicleId)", body: body)
            await onUpdated()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSaving = false
    }
}
