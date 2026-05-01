// SettingsView.swift
// Full settings screen — export, app info, sign out.
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showExportSheet  = false
    @State private var exportURL:        URL?
    @State private var isExporting      = false
    @State private var exportError:      String?
    @State private var showExportError  = false

    private let config = AppConfig.shared
    private let api    = NetworkService.shared

    var body: some View {
        NavigationStack {
            List {

                // ── Export ────────────────────────────────────────────────────
                Section {
                    Button {
                        Task { await exportCSV() }
                    } label: {
                        HStack {
                            Label("Export Trips to CSV", systemImage: "square.and.arrow.up")
                                .foregroundStyle(AppColors.accent)
                            Spacer()
                            if isExporting { ProgressView().tint(AppColors.accent) }
                        }
                    }
                    .disabled(isExporting)
                } header: {
                    Text("Export")
                } footer: {
                    Text("Exports all trips with date, vehicle, distance, and purpose. Useful for mileage reimbursement and tax records.")
                        .font(.caption)
                }

                // ── App info ──────────────────────────────────────────────────
                Section("App Info") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    LabeledContent("Region") {
                        Text(config.awsRegion)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    LabeledContent("User Pool") {
                        Text(config.userPoolId)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    LabeledContent("Receipts Bucket") {
                        Text(config.receiptsBucket)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }

                // ── Account ───────────────────────────────────────────────────
                Section("Account") {
                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle("Settings")
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: { Text(exportError ?? "Unknown error") }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportURL {
                    ShareSheet(url: url)
                }
            }
        }
    }

    // MARK: - CSV Export
    private func exportCSV() async {
        isExporting = true
        do {
            // Fetch trips and vehicles concurrently
            async let trips:    [Trip]    = api.get("trips")
            async let vehicles: [Vehicle] = api.get("vehicles")
            let (t, v) = try await (trips, vehicles)

            let vehicleMap = Dictionary(uniqueKeysWithValues: v.map { ($0.vehicleId, $0.name) })
            let sorted     = t.sorted { $0.tripDate > $1.tripDate }

            var csv = "Date,Vehicle,Distance (mi),GPS Distance (mi),Odometer Distance (mi),Purpose,Notes\n"
            for trip in sorted {
                let vName    = vehicleMap[trip.vehicleId] ?? "Unknown"
                let distance = String(format: "%.2f", trip.distance)
                let gps      = String(format: "%.2f", trip.gpsDistance)
                let odo      = String(format: "%.2f", trip.odometerDistance)
                let purpose  = trip.purpose.replacingOccurrences(of: ",", with: ";")
                let notes    = trip.notes.replacingOccurrences(of: ",", with: ";")
                csv += "\(trip.tripDate),\(vName),\(distance),\(gps),\(odo),\(purpose),\(notes)\n"
            }

            // Write to temp file
            let fileName = "trips_\(formattedToday()).csv"
            let tempURL  = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)

            exportURL = tempURL
            showExportSheet = true
        } catch {
            exportError    = error.localizedDescription
            showExportError = true
        }
        isExporting = false
    }

    private func formattedToday() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - UIActivityViewController wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
