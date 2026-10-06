import SwiftUI

struct MoodCheckInView: View {
    @EnvironmentObject var moodEngine: MoodEngine
    @EnvironmentObject var sensors: SensorHub
    @EnvironmentObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var showPaywall = false
    @State private var usingCamera = false

    var body: some View {
        ZStack {
            AuroraBackground(tint: moodEngine.mood?.color ?? Theme.accent)
            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                }
                Spacer(minLength: 0)

                Text(title)
                    .font(.system(.title, design: .serif).weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Button(action: orbTapped) {
                    MoodOrb(color: moodEngine.mood?.color ?? Theme.accent,
                            level: CGFloat(moodEngine.level), size: 170)
                        .overlay {
                            Image(systemName: moodEngine.phase == .listening ? "stop.fill" :
                                    (moodEngine.mood?.symbol ?? "mic.fill"))
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }
                .buttonStyle(.plain)

                Group {
                    switch moodEngine.phase {
                    case .idle:
                        Text("Tap the orb and tell me about your day.\nI listen to your words, tone and pace — all on-device.")
                    case .listening:
                        Text(moodEngine.transcript.isEmpty ? "Listening…" : "“\(moodEngine.transcript)”")
                    case .analyzing:
                        Text("Reading your mood…")
                    case .done:
                        if let mood = moodEngine.mood {
                            VStack(spacing: 8) {
                                Text(mood.blurb)
                                Text("\(moodEngine.explanation) · \(Int(moodEngine.confidence * 100))% sure")
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 24)
                .frame(minHeight: 70)

                if moodEngine.phase == .done {
                    Button("Show me books") { dismiss() }
                        .buttonStyle(GradientButtonStyle())
                        .padding(.horizontal, 40)
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Text("Or pick one").font(.caption).foregroundStyle(Theme.dim)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Mood.allCases) { m in
                                Button {
                                    moodEngine.mood = m; moodEngine.explanation = "You picked it."; moodEngine.confidence = 1
                                    moodEngine.phase = .done
                                } label: { Chip(text: m.title, symbol: m.symbol, selected: moodEngine.mood == m) }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    HStack {
                        TextField("…or type how you feel", text: $typed)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .glass(radius: 14)
                            .onSubmit(analyzeTyped)
                        Button(action: analyzeTyped) {
                            Image(systemName: "arrow.up").font(.headline).foregroundStyle(.black)
                                .padding(12).background(Theme.brandGradient, in: Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                if let err = moodEngine.errorMessage {
                    Text(err).font(.caption).foregroundStyle(Theme.warm)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onDisappear {
            if moodEngine.phase == .listening { moodEngine.stopAndAnalyze(expression: nil) }
            if usingCamera { sensors.stop(); usingCamera = false }
        }
    }

    private var title: String {
        switch moodEngine.phase {
        case .listening: return "I'm listening"
        case .done: return "Feeling \(moodEngine.mood?.title.lowercased() ?? "")"
        default: return "How are you feeling?"
        }
    }

    private func orbTapped() {
        guard store.isPlus else { showPaywall = true; return }
        if moodEngine.phase == .listening {
            moodEngine.stopAndAnalyze(expression: usingCamera && sensors.faceVisible ? sensors.expression : nil)
            if usingCamera { sensors.stop(); usingCamera = false }
        } else {
            // Read facial expression too, when the TrueDepth camera exists.
            if sensors.isSupported && !usingCamera { sensors.gestureDetectionEnabled = false; sensors.start(); usingCamera = true }
            Task { await moodEngine.startListening() }
        }
    }

    private func analyzeTyped() {
        let t = typed.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        moodEngine.analyze(text: t)
        typed = ""
    }
}
