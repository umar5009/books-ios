import SwiftUI

@main
struct LumaReadApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var recommender = RecommendationEngine.shared
    @StateObject private var sensors = SensorHub.shared
    @StateObject private var mood = MoodEngine()
    @StateObject private var store = SubscriptionStore()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(recommender)
                .environmentObject(sensors)
                .environmentObject(mood)
                .environmentObject(store)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Group {
            if settings.hasOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: settings.hasOnboarded)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("For You", systemImage: "sparkles") }
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            ProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}
