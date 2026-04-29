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
            VehiclesView()
                .tabItem { Label("Vehicles", systemImage: "car.fill") }
            TripsView()
                .tabItem { Label("Trips", systemImage: "map.fill") }
            ExpensesView()
                .tabItem { Label("Expenses", systemImage: "creditcard.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(AppColors.accent)
    }
}

// MARK: - Settings
struct SettingsView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .background(AppColors.background)
        }
    }
}
