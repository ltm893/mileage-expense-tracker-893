// MileageTracker893App.swift
import SwiftUI

@main
struct MileageTracker893App: App {

    @StateObject private var authService = AuthService()

    init() {
        NetworkService.shared.authService = nil
        applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .onAppear {
                    NetworkService.shared.authService = authService
                }
        }
    }

    private func applyAppearance() {
        let primary = UIColor(AppColors.primary)
        let bg      = UIColor(AppColors.background)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor          = bg
        nav.titleTextAttributes      = [.foregroundColor: primary]
        nav.largeTitleTextAttributes = [.foregroundColor: primary]

        UINavigationBar.appearance().standardAppearance   = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor            = primary
        UITabBar.appearance().tintColor                   = primary
        UITabBar.appearance().backgroundColor             = bg
        UITableView.appearance().backgroundColor          = bg
    }
}

// MARK: - App color palette (one place, used everywhere)
enum AppColors {
    static let primary     = Color(red: 0.08, green: 0.20, blue: 0.35)
    static let background  = Color(red: 0.97, green: 0.97, blue: 0.96)
    static let accent      = Color(red: 0.07, green: 0.36, blue: 0.42)
    static let destructive = Color.red
}
