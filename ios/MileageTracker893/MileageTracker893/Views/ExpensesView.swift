// ExpensesView.swift
import SwiftUI
import Combine

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

    func vehicleName(for id: String?) -> String {
        guard let id else { return "General" }
        return vehicles.first { $0.vehicleId == id }?.name ?? "Unknown Vehicle"
    }

    var totalAmount: Double { expenses.reduce(0) { $0 + $1.amount } }
}

// MARK: - ExpensesView
struct ExpensesView: View {
    @StateObject private var vm = ExpensesViewModel()
    @State private var showAdd  = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.expenses.isEmpty {
                    ProgressView("Loading expenses…")
                        .tint(AppColors.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.expenses.isEmpty {
                    ContentUnavailableView("No Expenses", systemImage: "creditcard.fill",
                        description: Text("Tap + to log your first expense."))
                } else {
                    List {
                        Section {
                            HStack {
                                Text("Total")
                                    .font(.headline)
                                    .foregroundStyle(AppColors.primary)
                                Spacer()
                                Text(String(format: "$%.2f", vm.totalAmount))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                        ForEach(vm.expenses) { expense in
                            NavigationLink(destination: ExpenseDetailView(
                                expense: expense,
                                vehicles: vm.vehicles,
                                vehicleName: vm.vehicleName(for: expense.vehicleId),
                                onUpdated: { await vm.load() }
                            )) {
                                ExpenseRow(
                                    expense:     expense,
                                    vehicleName: vm.vehicleName(for: expense.vehicleId)
                                )
                            }
                        }
                        .onDelete { indexSet in
                            Task { for i in indexSet { await vm.delete(vm.expenses[i]) } }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppColors.background)
            .navigationTitle("Expenses")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .tint(AppColors.accent)
                }
            }
            .sheet(isPresented: $showAdd) {
                AddExpenseView(vehicles: vm.vehicles) { await vm.load() }
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: { Text(vm.errorMessage ?? "") })
            .task { await vm.load() }
        }
    }
}

// MARK: - Expense row
struct ExpenseRow: View {
    let expense:     Expense
    let vehicleName: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.accentTint)
                    .frame(width: 40, height: 40)
                Image(systemName: expense.category.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(expense.category.displayName)
                        .font(.headline)
                        .foregroundStyle(AppColors.primary)
                    Spacer()
                    Text(expense.amountFormatted)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppColors.accent)
                }
                HStack(spacing: 4) {
                    if !expense.merchant.isEmpty {
                        Text(expense.merchant)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.secondaryText)
                        Text("·")
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Text(expense.expenseDate)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.secondaryText)
                }
                if expense.ocrStatus == .pending {
                    Label("Processing receipt…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                } else if expense.ocrStatus == .complete {
                    Label("Receipt scanned", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(AppColors.success)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Expense sheet
struct AddExpenseView: View {
    let vehicles: [Vehicle]
    var onSaved:  () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isVehicleExpense  = false
    @State private var selectedVehicleId = ""
    @State private var category          = ExpenseCategory.other
    @State private var amount            = ""
    @State private var expenseDate       = Date()
    @State private var merchant          = ""
    @State private var notes             = ""

    @State private var receiptImage:    UIImage?
    @State private var showSourcePicker = false
    @State private var showCamera       = false
    @State private var showLibrary      = false
    @State private var isScanning       = false
    @State private var isSaving         = false
    @State private var scanBadge:         String? = nil
    @State private var showError        = false
    @State private var errorMessage     = ""

    private let api = NetworkService.shared
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var cleanedAmount: String {
        amount.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
    }
    private var parsedAmount: Double { Double(cleanedAmount) ?? 0 }
    private var canSave: Bool {
        guard parsedAmount > 0 else { return false }
        if isVehicleExpense { return !selectedVehicleId.isEmpty }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                expenseTypeSection
                categorySection
                receiptSection
                detailsSection
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
            .background(AppColors.background)
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(AppColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave || isSaving)
                        .fontWeight(.semibold)
                        .tint(AppColors.accent)
                }
            }
            .onAppear {
                if selectedVehicleId.isEmpty, let first = vehicles.first {
                    selectedVehicleId = first.vehicleId
                }
            }
            .alert("Save Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
            .confirmationDialog("Add Receipt Photo", isPresented: $showSourcePicker, titleVisibility: .visible) {
                Button("Take Photo")           { showCamera  = true }
                Button("Choose from Library")  { showLibrary = true }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker(sourceType: .camera) { image in
                    receiptImage = image
                    Task { await scanReceipt(image) }
                }
            }
            .fullScreenCover(isPresented: $showLibrary) {
                CameraImagePicker(sourceType: .photoLibrary) { image in
                    receiptImage = image
                    Task { await scanReceipt(image) }
                }
            }
        }
    }

    private var expenseTypeSection: some View {
        Section {
            Toggle("Vehicle Expense", isOn: $isVehicleExpense)
                .tint(AppColors.accent)
                .onChange(of: isVehicleExpense) { _, on in
                    category = on ? .fuel : .other
                }
            if isVehicleExpense {
                if vehicles.isEmpty {
                    Text("Add a vehicle first.").foregroundStyle(AppColors.secondaryText)
                } else {
                    Picker("Vehicle", selection: $selectedVehicleId) {
                        ForEach(vehicles) { v in Text(v.name).tag(v.vehicleId) }
                    }
                    .tint(AppColors.accent)
                }
            }
        } header: { Text("Type") } footer: {
            Text(isVehicleExpense
                 ? "Linked to selected vehicle."
                 : "General expense — not linked to any vehicle.")
            .font(.caption)
        }
    }

    private var categorySection: some View {
        Section("Category") {
            Picker("Category", selection: $category) {
                if isVehicleExpense {
                    Section("Vehicle") {
                        ForEach(ExpenseCategory.vehicleCategories, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                }
                Section("General") {
                    ForEach(ExpenseCategory.generalCategories, id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.icon).tag(cat)
                    }
                }
            }
            .tint(AppColors.accent)
        }
    }

    private var receiptSection: some View {
        Section {
            if let receiptImage {
                VStack(alignment: .leading, spacing: 8) {
                    Image(uiImage: receiptImage)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 180).cornerRadius(10)
                    HStack {
                        if isScanning {
                            ProgressView().tint(AppColors.accent)
                            Text("Scanning…").font(.caption).foregroundStyle(AppColors.secondaryText)
                        } else if let badge = scanBadge {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.success)
                            Text(badge).font(.caption).foregroundStyle(AppColors.success)
                        }
                        Spacer()
                        Button("Retake") { showSourcePicker = true }
                            .font(.caption).foregroundStyle(AppColors.accent)
                    }
                }
            } else {
                Button { showSourcePicker = true } label: {
                    Label("Add Receipt Photo", systemImage: "camera.fill")
                        .foregroundStyle(AppColors.accent)
                }
            }
        } header: { Text("Receipt") } footer: {
            Text("Photo scanned automatically to fill in amount, date, and merchant.")
                .font(.caption)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            HStack {
                Text("$").foregroundStyle(AppColors.secondaryText)
                TextField("Amount", text: $amount).keyboardType(.decimalPad)
                if parsedAmount > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success).font(.caption)
                }
            }
            DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
                .tint(AppColors.accent)
            HStack {
                TextField("Merchant / Vendor (optional)", text: $merchant)
                if !merchant.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success).font(.caption)
                }
            }
            TextField("Notes (optional)", text: $notes)
        }
    }

    private func scanReceipt(_ image: UIImage) async {
        isScanning = true; scanBadge = nil
        let result = await ReceiptScanner.scan(image)
        if let v = result.amount, amount.isEmpty {
            amount = v.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
        }
        if let v = result.merchant, merchant.isEmpty { merchant = v }
        if let v = result.date {
            for format in ["MM/dd/yyyy", "M/d/yyyy", "MM-dd-yyyy", "MMMM d yyyy", "MMM d, yyyy"] {
                let f = DateFormatter(); f.dateFormat = format
                if let d = f.date(from: v) { expenseDate = d; break }
            }
        }
        isScanning = false
        var extracted: [String] = []
        if result.amount   != nil { extracted.append("amount") }
        if result.merchant != nil { extracted.append("merchant") }
        if result.date     != nil { extracted.append("date") }
        scanBadge = extracted.isEmpty ? "No data extracted" : "Scanned: \(extracted.joined(separator: ", "))"
    }

    private func save() async {
        isSaving = true
        do {
            let body = CreateExpenseRequest(
                vehicleId:   isVehicleExpense ? selectedVehicleId : nil,
                tripId:      nil,
                category:    category.rawValue,
                amount:      parsedAmount,
                expenseDate: Self.df.string(from: expenseDate),
                merchant:    merchant,
                notes:       notes
            )
            let created: Expense = try await api.post("expenses", body: body)
            await onSaved()
            dismiss()
            if let image = receiptImage {
                Task {
                    do {
                        let s3Key = try await ReceiptUploader.upload(
                            image: image, expenseId: created.expenseId, api: NetworkService.shared
                        )
                        let updateBody = UpdateExpenseRequest(
                            vehicleId:    isVehicleExpense ? selectedVehicleId : nil,
                            tripId:       nil,
                            category:     category.rawValue,
                            amount:       parsedAmount,
                            expenseDate:  Self.df.string(from: expenseDate),
                            merchant:     merchant,
                            notes:        notes,
                            receiptS3Key: s3Key
                        )
                        let _: Expense = try await NetworkService.shared.put(
                            "expenses/\(created.expenseId)", body: updateBody
                        )
                    } catch { print("Receipt upload failed: \(error)") }
                }
            }
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
            showError    = true
            return
        }
        isSaving = false
    }
}

// MARK: - Expense Detail (read + edit)
struct ExpenseDetailView: View {
    let expense:     Expense
    let vehicles:    [Vehicle]
    let vehicleName: String
    var onUpdated:   () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing        = false
    @State private var isSaving         = false
    @State private var showError        = false
    @State private var errorMessage     = ""

    // Edit state — initialised in .onAppear
    @State private var isVehicleExpense  = false
    @State private var selectedVehicleId = ""
    @State private var category          = ExpenseCategory.other
    @State private var amount            = ""
    @State private var expenseDate       = Date()
    @State private var merchant          = ""
    @State private var notes             = ""

    private let api = NetworkService.shared
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let displayDF: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    private var parsedAmount: Double {
        Double(amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) ?? 0
    }
    private var canSave: Bool {
        guard parsedAmount > 0 else { return false }
        if isVehicleExpense { return !selectedVehicleId.isEmpty }
        return true
    }

    var body: some View {
        List {
            if isEditing {
                editSections
            } else {
                readSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(isEditing ? "Edit Expense" : expense.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .tint(AppColors.accent)
                        .disabled(!canSave || isSaving)
                } else {
                    Button("Edit") { isEditing = true }
                        .tint(AppColors.accent)
                }
            }
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { resetEditState(); isEditing = false }
                        .tint(AppColors.secondaryText)
                }
            }
        }
        .alert("Save Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage) }
        .onAppear { resetEditState() }
    }

    // MARK: - Read-only view
    private var readSections: some View {
        Group {
            Section("Expense") {
                LabeledContent("Category", value: expense.category.displayName)
                LabeledContent("Amount",   value: expense.amountFormatted)
                LabeledContent("Date",     value: expense.expenseDate)
                LabeledContent("Type",     value: expense.isVehicleExpense ? vehicleName : "General")
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
                            Text(item.description).foregroundStyle(AppColors.secondaryText)
                            Spacer()
                            Text(item.amount).foregroundStyle(AppColors.primary)
                        }
                        .font(.caption)
                    }
                }
            } else if expense.ocrStatus == .pending {
                Section {
                    Label("Processing receipt…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(AppColors.warning)
                }
            }
        }
    }

    // MARK: - Edit sections
    private var editSections: some View {
        Group {
            Section {
                Toggle("Vehicle Expense", isOn: $isVehicleExpense)
                    .tint(AppColors.accent)
                    .onChange(of: isVehicleExpense) { _, on in
                        if on && selectedVehicleId.isEmpty, let first = vehicles.first {
                            selectedVehicleId = first.vehicleId
                        }
                    }
                if isVehicleExpense {
                    if vehicles.isEmpty {
                        Text("Add a vehicle first.").foregroundStyle(AppColors.secondaryText)
                    } else {
                        Picker("Vehicle", selection: $selectedVehicleId) {
                            ForEach(vehicles) { v in Text(v.name).tag(v.vehicleId) }
                        }
                        .tint(AppColors.accent)
                    }
                }
            } header: { Text("Type") }

            Section("Category") {
                Picker("Category", selection: $category) {
                    if isVehicleExpense {
                        Section("Vehicle") {
                            ForEach(ExpenseCategory.vehicleCategories, id: \.self) { cat in
                                Label(cat.displayName, systemImage: cat.icon).tag(cat)
                            }
                        }
                    }
                    Section("General") {
                        ForEach(ExpenseCategory.generalCategories, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                }
                .tint(AppColors.accent)
            }

            Section("Details") {
                HStack {
                    Text("$").foregroundStyle(AppColors.secondaryText)
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                }
                DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
                    .tint(AppColors.accent)
                TextField("Merchant / Vendor", text: $merchant)
                TextField("Notes", text: $notes)
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
        isVehicleExpense  = expense.vehicleId != nil
        selectedVehicleId = expense.vehicleId ?? ""
        category          = expense.category
        amount            = String(format: "%.2f", expense.amount)
        merchant          = expense.merchant
        notes             = expense.notes

        // Parse stored date string back to Date
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        expenseDate = f.date(from: expense.expenseDate) ?? Date()
    }

    private func save() async {
        isSaving = true
        do {
            let body = UpdateExpenseRequest(
                vehicleId:    isVehicleExpense ? selectedVehicleId : nil,
                tripId:       expense.tripId,
                category:     category.rawValue,
                amount:       parsedAmount,
                expenseDate:  Self.df.string(from: expenseDate),
                merchant:     merchant,
                notes:        notes,
                receiptS3Key: expense.receiptS3Key
            )
            let _: Expense = try await api.put("expenses/\(expense.expenseId)", body: body)
            await onUpdated()
            isEditing = false
        } catch {
            errorMessage = error.localizedDescription
            showError    = true
        }
        isSaving = false
    }
}
