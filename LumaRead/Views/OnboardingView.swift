import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var recommender: RecommendationEngine
    @State private var page = 0
    @State private var picks: Set<String> = []

    var body: some View {
        ZStack {
            AuroraBackground()
            TabView(selection: $page) {
                welcome.tag(0)
                features.tag(1)
                interests.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            MoodOrb(size: 150).frame(height: 210)
            Text("LumaRead").font(.system(size: 46, weight: .bold, design: .serif)).foregroundStyle(.white)
            Text("Books that read the room.\nPages that follow your eyes.")
                .multilineTextAlignment(.center).font(.title3).foregroundStyle(Theme.dim)
            Spacer()
            Button("Begin") { withAnimation { page = 1 } }.buttonStyle(GradientButtonStyle()).padding(.horizontal, 40)
            Spacer().frame(height: 50)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer()
            feature("eye.fill", "Eye-Flow", "The line and word you're reading glow softly. Reach the end — the page turns itself.")
            feature("hand.raised.fingers.spread", "Air Zoom", "Spread two fingers in the air for bigger text, pinch for smaller. No touching.")
            feature("waveform", "Mood AI", "Tell me how your day was. I'll pick a book that fits — or lifts — your mood.")
            feature("sparkles", "A feed that learns you", "Every scroll and minute read trains your private, on-device taste model.")
            Spacer()
            Button("Next") { withAnimation { page = 2 } }.buttonStyle(GradientButtonStyle())
            Spacer().frame(height: 50)
        }
        .padding(.horizontal, 28)
    }

    private var interests: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            Text("What do you love?").font(.system(.largeTitle, design: .serif).bold()).foregroundStyle(.white)
            Text("Pick 3 or more to train your feed").foregroundStyle(Theme.dim)
            ScrollView {
                FlowLayout(spacing: 10) {
                    ForEach(DiscoverView.topics, id: \.self) { t in
                        Button {
                            if picks.contains(t) { picks.remove(t) } else { picks.insert(t) }
                        } label: { Chip(text: t, selected: picks.contains(t)) }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
            Button("Start reading") {
                recommender.seed(interests: Array(picks))
                settings.hasOnboarded = true
            }
            .buttonStyle(GradientButtonStyle())
            .padding(.horizontal, 40)
            .disabled(picks.count < 3)
            .opacity(picks.count < 3 ? 0.5 : 1)
            Spacer().frame(height: 50)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Theme.brandGradient).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(text).font(.subheadline).foregroundStyle(Theme.dim)
            }
        }
    }
}
