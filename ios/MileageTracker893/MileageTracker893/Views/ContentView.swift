// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        Group {
            if auth.isSignedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isSignedIn)
    }
}

// MARK: - Main tab bar
struct MainTabView: View {
    var body: some View {
        TabView {
            TripsView()
                .tabItem { Label("Trips", systemImage: "map.fill") }
            ExpensesView()
                .tabItem { Label("Expenses", systemImage: "creditcard.fill") }
            VehiclesView()
                .tabItem { Label("Vehicles", systemImage: "car.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(AppColors.accent)
    }
}
