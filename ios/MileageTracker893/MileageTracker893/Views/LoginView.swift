// LoginView.swift
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService

    @State private var email        = ""
    @State private var password     = ""
    @State private var showPassword = false
    @State private var isLoading    = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                VStack(spacing: 32) {
                    VStack(spacing: 8) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(AppColors.primary)
                        Text("MileageTracker893")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppColors.primary)
                        Text("Track trips & expenses")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)

                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Password", text: $password)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField("Password", text: $password)
                                }
                            }
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

                        if let error = auth.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(AppColors.destructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            Task { await signIn() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Sign In").fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canSubmit ? AppColors.primary : Color.gray.opacity(0.4))
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                        }
                        .disabled(!canSubmit)
                    }
                    .padding(.horizontal, 28)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !isLoading }

    private func signIn() async {
        isLoading = true
        auth.errorMessage = nil
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            auth.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
