import SwiftUI

/// User-facing preferences, persisted with @AppStorage.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("hasOnboarded") var hasOnboarded = false
    @AppStorage("readerFontSize") var fontSize: Double = 20
    @AppStorage("readerTheme") var readerThemeRaw = ReaderTheme.night.rawValue

    // Hands-free features
    @AppStorage("eyeTrackingEnabled") var eyeTrackingEnabled = true
    @AppStorage("autoPageTurn") var autoPageTurn = true
    @AppStorage("wordHighlight") var wordHighlight = true
    @AppStorage("doubleBlinkTurn") var doubleBlinkTurn = true
    @AppStorage("airZoomEnabled") var airZoomEnabled = true
    @AppStorage("showGazeDot") var showGazeDot = false

    // Mood
    @AppStorage("moodLift") var moodLift = true   // lift low moods instead of mirroring them

    var readerTheme: ReaderTheme {
        get { ReaderTheme(rawValue: readerThemeRaw) ?? .night }
        set { readerThemeRaw = newValue.rawValue; objectWillChange.send() }
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case night, paper, sepia, midnightBlue
    var id: String { rawValue }

    var background: Color {
        switch self {
        case .night: return Color(red: 0.06, green: 0.05, blue: 0.10)
        case .paper: return Color(red: 0.98, green: 0.97, blue: 0.95)
        case .sepia: return Color(red: 0.96, green: 0.91, blue: 0.80)
        case .midnightBlue: return Color(red: 0.05, green: 0.09, blue: 0.18)
        }
    }
    var text: Color {
        switch self {
        case .night, .midnightBlue: return Color.white.opacity(0.88)
        case .paper: return Color(white: 0.12)
        case .sepia: return Color(red: 0.30, green: 0.22, blue: 0.14)
        }
    }
    var lineHighlight: Color {
        switch self {
        case .night, .midnightBlue: return Theme.accent.opacity(0.18)
        case .paper: return Theme.accent.opacity(0.12)
        case .sepia: return Color.orange.opacity(0.16)
        }
    }
    var wordHighlight: Color {
        switch self {
        case .sepia: return Color.orange.opacity(0.45)
        default: return Theme.accent2.opacity(0.45)
        }
    }
    var name: String {
        switch self {
        case .night: return "Night"
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .midnightBlue: return "Ocean"
        }
    }
}
