// ExpensesView.swift
import SwiftUI
import Combine
import PhotosUI

@MainActor
final class ExpensesViewModel: ObservableObject {
    @Published var expenses:     [Expense]  = []
    @Published var vehicles:     [Vehicle]  = []
    @Published var isLoading:    Bool       = false
    @Published var errorMessage: String?    = nil

    private let api = NetworkService.shared

    func load() async {
        isLoading = true; errorMessage = nil
        do {
            async let e: [Expense] = api.get("expenses")
            async let v: [Vehicle] = api.get("vehicles")
            (expenses, vehicles) = try await (e, v)
            expenses.sort { $0.expenseDate > $1.expenseDate }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func delete(_ expense: Expense) async {
        do {
            let _: DeleteResponse = try await api.delete("expenses/\(expense.expenseId)")
            expenses.removeAll { $0.expenseId == expense.expenseId }
        } catch { errorMessage = error.localizedDescription }
    }

    func vehicleName(for id: String) -> String {
        vehicles.first { $0.vehicleId == id }?.name ?? "Unknown Vehicle"
    }

    var totalAmount: Double { expenses.reduce(0) { $0 + $1.amount } }
}

struct ExpensesView: View {
    @StateObject private var vm = ExpensesViewModel()
    @State private var showAdd  = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.expenses.isEmpty {
                    ProgressView("Loading expenses…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.expenses.isEmpty {
                    ContentUnavailableView("No Expenses", systemImage: "creditcard.fill",
                        description: Text("Tap + to log your first expense."))
                } else {
                    List {
                        Section {
                            HStack {
                                Label("Total", systemImage: "sum").foregroundStyle(AppColors.primary)
                                Spacer()
                                Text(String(format: "$%.2f", vm.totalAmount))
                                    .font(.headline).foregroundStyle(AppColors.accent)
                            }
                        }
                        ForEach(vm.expenses) { expense in
                            NavigationLink(destination: ExpenseDetailView(
                                expense: expense,
                                vehicleName: vm.vehicleName(for: expense.vehicleId),
                                onUpdated: { await vm.load() }
                            )) {
                                ExpenseRow(expense: expense,
                                           vehicleName: vm.vehicleName(for: expense.vehicleId))
                            }
                        }
                        .onDelete { indexSet in
                            Task { for i in indexSet { await vm.delete(vm.expenses[i]) } }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Expenses")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddExpenseView(vehicles: vm.vehicles) { await vm.load() }
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: { Text(vm.errorMessage ?? "") })
            .task { await vm.load() }
            .background(AppColors.background)
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense; let vehicleName: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.icon)
                .font(.title2).foregroundStyle(AppColors.accent).frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(expense.category.displayName).font(.headline).foregroundStyle(AppColors.primary)
                    Spacer()
                    Text(expense.amountFormatted).font(.headline).foregroundStyle(AppColors.accent)
                }
                Text(vehicleName + " · " + expense.expenseDate).font(.caption).foregroundStyle(.secondary)
                if !expense.merchant.isEmpty {
                    Text(expense.merchant).font(.caption).foregroundStyle(.secondary)
                }
                if expense.ocrStatus == .pending {
                    Label("Processing receipt…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2).foregroundStyle(.orange)
                } else if expense.ocrStatus == .complete {
                    Label("Receipt scanned", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddExpenseView: View {
    let vehicles: [Vehicle]
    var onSaved:  () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVehicleId = ""
    @State private var category          = ExpenseCategory.fuel
    @State private var amount            = ""
    @State private var expenseDate       = Date()
    @State private var merchant          = ""
    @State private var notes             = ""
    @State private var isSaving          = false
    @State private var isUploadingPhoto  = false
    @State private var selectedPhoto:      PhotosPickerItem?
    @State private var receiptImage:       UIImage?
    @State private var errorMessage:       String?

    private let api = NetworkService.shared
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        NavigationStack {
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
                Section("Expense") {
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    HStack {
                        Text("$")
                        TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    }
                    DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
                    TextField("Merchant (optional)", text: $merchant)
                    TextField("Notes (optional)",    text: $notes)
                }
                Section("Receipt") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        if let receiptImage {
                            Image(uiImage: receiptImage)
                                .resizable().scaledToFit()
                                .frame(maxHeight: 160).cornerRadius(8)
                        } else {
                            Label("Attach Receipt Photo", systemImage: "camera.fill")
                        }
                    }
                    .onChange(of: selectedPhoto) { _, item in Task { await loadPhoto(item) } }
                    if isUploadingPhoto {
                        HStack {
                            ProgressView()
                            Text("Uploading…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(AppColors.destructive).font(.caption) }
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave || isSaving || isUploadingPhoto)
                }
            }
            .onAppear {
                if selectedVehicleId.isEmpty, let first = vehicles.first {
                    selectedVehicleId = first.vehicleId
                }
            }
        }
    }

    private var canSave: Bool { !selectedVehicleId.isEmpty && Double(amount) != nil }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data  = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        receiptImage = image
    }

    private func save() async {
        isSaving = true; errorMessage = nil
        do {
            let body = CreateExpenseRequest(
                vehicleId:   selectedVehicleId, tripId: nil,
                category:    category.rawValue,
                amount:      Double(amount) ?? 0,
                expenseDate: Self.df.string(from: expenseDate),
                merchant:    merchant, notes: notes
            )
            let created: Expense = try await api.post("expenses", body: body)

            if receiptImage != nil,
               let authSvc = NetworkService.shared.authService {
                isUploadingPhoto = true
                let s3Key = "receipts/\(created.expenseId).jpg"
                let _ = try await authSvc.idToken()
                let updateBody = UpdateExpenseRequest(
                    vehicleId:    selectedVehicleId, tripId: nil,
                    category:     category.rawValue,
                    amount:       Double(amount) ?? 0,
                    expenseDate:  Self.df.string(from: expenseDate),
                    merchant:     merchant, notes: notes,
                    receiptS3Key: s3Key
                )
                let _: Expense = try await api.put("expenses/\(created.expenseId)", body: updateBody)
                isUploadingPhoto = false
            }
            await onSaved(); dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isUploadingPhoto = false
        }
        isSaving = false
    }
}

struct ExpenseDetailView: View {
    let expense:     Expense
    let vehicleName: String
    var onUpdated:   () async -> Void

    var body: some View {
        List {
            Section("Expense") {
                LabeledContent("Category", value: expense.category.displayName)
                LabeledContent("Amount",   value: expense.amountFormatted)
                LabeledContent("Date",     value: expense.expenseDate)
                LabeledContent("Vehicle",  value: vehicleName)
                if !expense.merchant.isEmpty { LabeledContent("Merchant", value: expense.merchant) }
                if !expense.notes.isEmpty    { LabeledContent("Notes",    value: expense.notes) }
            }
            if let ocr = expense.ocrData, expense.ocrStatus == .complete {
                Section("Scanned Receipt") {
                    if let total    = ocr.total    { LabeledContent("Total",    value: total) }
                    if let date     = ocr.date     { LabeledContent("Date",     value: date) }
                    if let merchant = ocr.merchant { LabeledContent("Merchant", value: merchant) }
                    ForEach(ocr.lineItems, id: \.description) { item in
                        HStack {
                            Text(item.description).foregroundStyle(.secondary)
                            Spacer()
                            Text(item.amount)
                        }
                        .font(.caption)
                    }
                }
            } else if expense.ocrStatus == .pending {
                Section {
                    Label("Receipt is being processed…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(expense.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColors.background)
    }
}
