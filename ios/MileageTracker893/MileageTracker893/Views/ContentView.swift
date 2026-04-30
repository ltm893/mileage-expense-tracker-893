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

// MARK: - Main tab bar (Trips - Expenses - Vehicles - Settings)
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

// MARK: - Settings
struct SettingsView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        auth.signOut()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(AppColors.destructive)
                            Text("Sign Out")
                                .foregroundStyle(AppColors.destructive)
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
