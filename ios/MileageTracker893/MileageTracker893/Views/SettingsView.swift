// SettingsView.swift
// Settings screen — app info and sign out.
// CSV export has moved to the Summary tab.
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService

    private let config = AppConfig.shared

    var body: some View {
        NavigationStack {
            List {

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
        }
    }
}
