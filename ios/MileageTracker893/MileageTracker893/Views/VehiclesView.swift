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
                    ProgressView("Loading vehicles…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.vehicles.isEmpty {
                    ContentUnavailableView("No Vehicles", systemImage: "car.fill",
                        description: Text("Tap + to add your first vehicle."))
                } else {
                    List {
                        ForEach(vm.vehicles) { vehicle in
                            NavigationLink(destination: VehicleDetailView(vehicle: vehicle, onUpdated: { await vm.load() })) {
                                VehicleRow(vehicle: vehicle)
                            }
                        }
                        .onDelete { indexSet in
                            Task { for i in indexSet { await vm.delete(vm.vehicles[i]) } }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Vehicles")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddVehicleView { await vm.load() } }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: { Text(vm.errorMessage ?? "") })
            .task { await vm.load() }
            .background(AppColors.background)
        }
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vehicle.name).font(.headline).foregroundStyle(AppColors.primary)
            Text("\(vehicle.year) \(vehicle.make) \(vehicle.model)").font(.subheadline).foregroundStyle(.secondary)
            Text("Odometer: \(String(format: "%.0f mi", vehicle.currentOdometer))").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct AddVehicleView: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name     = ""
    @State private var make     = ""
    @State private var model    = ""
    @State private var year     = Calendar.current.component(.year, from: Date())
    @State private var odometer = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let api = NetworkService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle Info") {
                    TextField("Nickname (e.g. My Truck)", text: $name)
                    TextField("Make (e.g. Ford)",         text: $make)
                    TextField("Model (e.g. F-150)",       text: $model)
                    Stepper("Year: \(year)", value: $year, in: 1980...2030)
                }
                Section("Odometer") {
                    TextField("Current miles", text: $odometer).keyboardType(.decimalPad)
                }
                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(AppColors.destructive).font(.caption) }
                }
            }
            .navigationTitle("Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(!canSave || isSaving)
                }
            }
        }
    }

    private var canSave: Bool { !name.isEmpty && !make.isEmpty && !model.isEmpty }

    private func save() async {
        isSaving = true
        do {
            let body = CreateVehicleRequest(name: name, make: make, model: model,
                                            year: year, currentOdometer: Double(odometer) ?? 0)
            let _: Vehicle = try await api.post("vehicles", body: body)
            await onSaved(); dismiss()
        } catch { errorMessage = error.localizedDescription }
        isSaving = false
    }
}

struct VehicleDetailView: View {
    let vehicle:   Vehicle
    var onUpdated: () async -> Void

    @State private var name     = ""
    @State private var make     = ""
    @State private var model    = ""
    @State private var year     = 2024
    @State private var odometer = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let api = NetworkService.shared

    var body: some View {
        Form {
            Section("Vehicle Info") {
                TextField("Nickname", text: $name)
                TextField("Make",     text: $make)
                TextField("Model",    text: $model)
                Stepper("Year: \(year)", value: $year, in: 1980...2030)
            }
            Section("Odometer") {
                TextField("Current miles", text: $odometer).keyboardType(.decimalPad)
            }
            if let error = errorMessage {
                Section { Text(error).foregroundStyle(AppColors.destructive).font(.caption) }
            }
        }
        .navigationTitle(vehicle.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(isSaving)
            }
        }
        .onAppear {
            name = vehicle.name; make = vehicle.make; model = vehicle.model
            year = vehicle.year; odometer = String(format: "%.0f", vehicle.currentOdometer)
        }
    }

    private func save() async {
        isSaving = true
        do {
            let body = UpdateVehicleRequest(name: name, make: make, model: model,
                                            year: year, currentOdometer: Double(odometer) ?? vehicle.currentOdometer)
            let _: Vehicle = try await api.put("vehicles/\(vehicle.vehicleId)", body: body)
            await onUpdated()
        } catch { errorMessage = error.localizedDescription }
        isSaving = false
    }
}
