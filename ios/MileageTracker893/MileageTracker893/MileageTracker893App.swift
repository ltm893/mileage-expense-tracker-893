// MileageTracker893App.swift
import SwiftUI

@main
struct MileageTracker893App: App {

    /// Wire API auth synchronously. Tab `.task` loaders can run before any `.onAppear`, which previously left `NetworkService.authService == nil` and caused bare GETs → HTTP 401.
    @StateObject private var authService = MileageTracker893App.bootstrapAuth()

    init() {
        applyAppearance()
    }

    private static func bootstrapAuth() -> AuthService {
        let service = AuthService()
        NetworkService.shared.authService = service
        return service
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
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
        // NOTE: Do NOT set UITableViewCell.appearance().backgroundColor globally —
        // it breaks keyboardType on TextFields inside SwiftUI Form/List by
        // interfering with the UIKit responder chain that SwiftUI uses internally.
    }
}
