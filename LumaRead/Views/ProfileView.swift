import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: SubscriptionStore
    @EnvironmentObject var sensors: SensorHub
    @EnvironmentObject var recommender: RecommendationEngine
    @State private var showPaywall = false
    @State private var showCalibration = false
    @State private var confirmReset = false

    private var topInterests: [String] {
        recommender.profile.tagAffinity.sorted { $0.value > $1.value }.prefix(10).map { $0.key.capitalized }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                Form {
                    Section {
                        Button { showPaywall = true } label: {
                            HStack {
                                Image(systemName: store.isPlus ? "crown.fill" : "sparkles")
                                    .foregroundStyle(Theme.brandGradient).font(.title2)
                                VStack(alignment: .leading) {
                                    Text(store.isPlus ? "LumaRead Plus" : "Upgrade to Plus").font(.headline)
                                    Text(store.isPlus ? "All hands-free & AI features unlocked" : "From $1.99/mo · 7 days free")
                                        .font(.caption).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                    }

                    Section("Your taste (learned on-device)") {
                        if topInterests.isEmpty {
                            Text("Keep browsing — your interests will appear here.").foregroundStyle(Theme.dim)
                        } else {
                            FlowLayout { ForEach(topInterests, id: \.self) { Chip(text: $0) } }
                                .padding(.vertical, 4)
                        }
                        Button("Reset my recommendations", role: .destructive) { confirmReset = true }
                    }

                    Section {
                        LabeledContent("Eye tracking", value: sensors.isSupported ? "Available" : "Needs Face ID iPhone")
                        Toggle("Follow my eyes", isOn: $settings.eyeTrackingEnabled)
                        Toggle("Auto page turn", isOn: $settings.autoPageTurn)
                        Toggle("Double-blink page turn", isOn: $settings.doubleBlinkTurn)
                        Toggle("Air Zoom gestures", isOn: $settings.airZoomEnabled)
                        Button("Calibrate eyes") { showCalibration = true }.disabled(!sensors.isSupported)
                    } header: { Text("Hands-free") }

                    Section {
                        Toggle("Lift low moods", isOn: $settings.moodLift)
                    } header: { Text("Mood AI") } footer: {
                        Text("When you sound down or stressed, suggest comforting reads instead of mirroring the mood.")
                    }

                    Section("Privacy") {
                        Text("Camera, voice and reading signals are processed on your iPhone. Nothing is recorded or uploaded; your taste profile never leaves the device.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("You")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .fullScreenCover(isPresented: $showCalibration) { CalibrationView() }
            .confirmationDialog("Forget everything LumaRead learned about your taste?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { recommender.reset() }
            }
        }
    }
}
