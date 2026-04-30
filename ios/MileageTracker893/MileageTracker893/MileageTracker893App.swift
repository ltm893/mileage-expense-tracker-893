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
        let accent  = UIColor(AppColors.accent)
        let bg      = UIColor(AppColors.background)
        let surface = UIColor(AppColors.surface)

        // ── Navigation bar ────────────────────────────────────────────────────
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor          = bg
        nav.titleTextAttributes      = [.foregroundColor: primary]
        nav.largeTitleTextAttributes = [.foregroundColor: primary]
        nav.shadowColor              = .clear

        UINavigationBar.appearance().standardAppearance   = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance    = nav
        UINavigationBar.appearance().tintColor            = accent

        // ── Tab bar ───────────────────────────────────────────────────────────
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = surface
        tab.stackedLayoutAppearance.selected.iconColor   = accent
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]
        tab.stackedLayoutAppearance.normal.iconColor     = UIColor(AppColors.secondaryText)
        tab.stackedLayoutAppearance.normal.titleTextAttributes  = [.foregroundColor: UIColor(AppColors.secondaryText)]

        UITabBar.appearance().standardAppearance  = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor           = accent

        // ── Table / List ──────────────────────────────────────────────────────
        UITableView.appearance().backgroundColor       = bg
        UITableViewCell.appearance().backgroundColor   = surface
    }
}
