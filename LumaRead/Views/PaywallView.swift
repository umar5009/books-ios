import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = "lumaread.plus.yearly"

    private let perks: [(String, String, String)] = [
        ("eye.fill", "Eye-Flow reading", "Highlights the line & word you're reading"),
        ("arrow.turn.down.right", "Hands-free page turns", "Auto-turn at the end of a page, or double-blink"),
        ("hand.raised.fingers.spread", "Air Zoom", "Spread or pinch fingers in the air to resize text"),
        ("waveform", "Mood AI", "Talk for 5 seconds, get books for how you feel"),
    ]

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 22) {
                    MoodOrb(size: 90).frame(height: 130).padding(.top, 20)
                    Text("LumaRead Plus").font(.system(.largeTitle, design: .serif).bold()).foregroundStyle(.white)
                    Text("Less than a coffee a month. 7 days free.").foregroundStyle(Theme.dim)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(perks, id: \.1) { p in
                            HStack(spacing: 14) {
                                Image(systemName: p.0).font(.title3).foregroundStyle(Theme.brandGradient).frame(width: 30)
                                VStack(alignment: .leading) {
                                    Text(p.1).font(.headline).foregroundStyle(.white)
                                    Text(p.2).font(.caption).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                    }
                    .padding(18).glass()

                    if store.products.isEmpty {
                        // Fallback display before StoreKit responds.
                        planRow(id: "lumaread.plus.monthly", name: "Monthly", price: "$1.99 / month", badge: nil)
                        planRow(id: "lumaread.plus.yearly", name: "Yearly", price: "$11.99 / year", badge: "Save 50%")
                        planRow(id: "lumaread.plus.lifetime", name: "Lifetime", price: "$24.99 once", badge: nil)
                    } else {
                        ForEach(store.products, id: \.id) { p in
                            planRow(id: p.id, name: p.displayName, price: p.displayPrice + suffix(p),
                                    badge: p.id.hasSuffix("yearly") ? "Save 50%" : nil)
                        }
                    }

                    Button("Start free trial") {
                        guard let p = store.products.first(where: { $0.id == selectedID }) else { return }
                        Task { await store.purchase(p); if store.isPlus { dismiss() } }
                    }
                    .buttonStyle(GradientButtonStyle())

                    HStack(spacing: 20) {
                        Button("Restore") { Task { await store.restore() } }
                        Button("Not now") { dismiss() }
                    }
                    .font(.footnote).foregroundStyle(Theme.dim)

                    #if DEBUG
                    Toggle("Debug: unlock all", isOn: $store.debugUnlock).font(.footnote).tint(Theme.accent)
                    #endif
                    if let e = store.purchaseError { Text(e).font(.caption).foregroundStyle(Theme.warm) }
                    Text("The entire classic library and AI feed stay free forever.")
                        .font(.caption2).foregroundStyle(Theme.dim)
                }
                .padding(22)
            }
        }
    }

    private func suffix(_ p: Product) -> String {
        guard let period = p.subscription?.subscriptionPeriod else { return " once" }
        return period.unit == .year ? " / year" : " / month"
    }

    private func planRow(id: String, name: String, price: String, badge: String?) -> some View {
        Button { selectedID = id } label: {
            HStack {
                Image(systemName: selectedID == id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedID == id ? Theme.accent2 : Theme.dim)
                Text(name).font(.headline)
                if let badge {
                    Text(badge).font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.warm, in: Capsule()).foregroundStyle(.black)
                }
                Spacer()
                Text(price).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(16)
            .glass(radius: 16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selectedID == id ? Theme.accent2 : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
