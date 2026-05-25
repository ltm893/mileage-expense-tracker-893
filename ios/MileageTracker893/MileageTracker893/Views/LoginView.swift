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

                    // ── Logo ──────────────────────────────────────────────────
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 88, height: 88)
                                .shadow(color: AppColors.accent.opacity(0.35), radius: 12, y: 6)
                            Image(systemName: "car.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white)
                        }

                        Text("MileageTracker893")
                            .font(.title.bold())
                            .foregroundStyle(AppColors.primary)

                        Text("Track trips & expenses")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .padding(.top, 60)

                    // ── Form ──────────────────────────────────────────────────
                    VStack(spacing: 14) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding()
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .shadow(color: AppColors.shadowColor, radius: 4, y: 2)

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
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                        .padding()
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .shadow(color: AppColors.shadowColor, radius: 4, y: 2)

                        if let error = auth.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(error)
                            }
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
                            .background(canSubmit ? AppColors.accent : AppColors.secondaryText.opacity(0.4))
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                            .shadow(color: AppColors.accent.opacity(canSubmit ? 0.35 : 0), radius: 8, y: 4)
                        }
                        .disabled(!canSubmit)
                        .animation(.easeInOut(duration: 0.2), value: canSubmit)
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
