// AppColors.swift
// MileageTracker893 color theme
//
// Palette:
//   Primary:     #1A2F4A  Dark navy       — headings, nav titles, primary text
//   Accent:      #114B5F  Dark teal       — buttons, icons, badges, toggles
//   AccentLight: #1ABCBA  Bright teal     — highlights, active states
//   Background:  #EEF8FA  Ice blue        — screen backgrounds
//   Surface:     #FFFFFF  White           — form cells, cards
//   Secondary:   #5A7A8A  Slate           — captions, subtitles, placeholders
//   Destructive: #D94F4F  Red             — delete, errors
//   Success:     #2A9D6F  Green           — scanned, saved confirmations
//   Warning:     #F5A623  Amber           — processing, pending states
//   Gold:        #F5C842  Yellow          — sparkle accent

import SwiftUI

enum AppColors {

    // ── Primary ───────────────────────────────────────────────────────────────
    static let primary       = Color(hex: "#1A2F4A")

    // ── Accent ────────────────────────────────────────────────────────────────
    static let accent        = Color(red: 17/255, green: 75/255, blue: 95/255)
    static let accentLight   = Color(hex: "#1ABCBA")

    // ── Backgrounds ───────────────────────────────────────────────────────────
    static let background    = Color(hex: "#EEF8FA")
    static let surface       = Color.white

    // ── Text ──────────────────────────────────────────────────────────────────
    static let secondaryText = Color(hex: "#5A7A8A")

    // ── Status ────────────────────────────────────────────────────────────────
    static let destructive   = Color(hex: "#D94F4F")
    static let success       = Color(hex: "#2A9D6F")
    static let warning       = Color(hex: "#F5A623")

    // ── Extras ────────────────────────────────────────────────────────────────
    static let gold          = Color(hex: "#F5C842")
    static let accentTint    = Color(red: 17/255, green: 75/255, blue: 95/255).opacity(0.12)
    static let shadowColor   = Color(hex: "#1A2F4A").opacity(0.06)
}

// MARK: - Color(hex:) initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
