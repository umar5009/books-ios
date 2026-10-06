import StoreKit

/// StoreKit 2 subscriptions. Priced well below Kindle Unlimited / Everand / Speechify.
///   • LumaRead Free  — full public-domain library, AI feed, classic reader
///   • LumaRead Plus  — $1.99/mo or $11.99/yr (7-day free trial): Eye-Flow reading, auto page turn,
///                      double-blink turns, Air Zoom, Mood AI
///   • Lifetime       — $24.99 one-time
@MainActor
final class SubscriptionStore: ObservableObject {
    static let productIDs = ["lumaread.plus.monthly", "lumaread.plus.yearly", "lumaread.plus.lifetime"]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPlus = false
    @Published var purchaseError: String?

    #if DEBUG
    /// Lets you test every feature in the simulator / on device without buying.
    @Published var debugUnlock = true { didSet { refreshEntitlements() } }
    #endif

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlementsAsync()
            }
        }
        Task { await loadProducts(); await refreshEntitlementsAsync() }
    }

    func loadProducts() async {
        do {
            let p = try await Product.products(for: Self.productIDs)
            products = p.sorted { $0.price < $1.price }
        } catch { purchaseError = error.localizedDescription }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let t) = verification { await t.finish() }
                await refreshEntitlementsAsync()
            case .userCancelled, .pending: break
            @unknown default: break
            }
        } catch { purchaseError = error.localizedDescription }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlementsAsync()
    }

    func refreshEntitlements() { Task { await refreshEntitlementsAsync() } }

    func refreshEntitlementsAsync() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.productIDs.contains(t.productID), t.revocationDate == nil { active = true }
        }
        #if DEBUG
        if debugUnlock { active = true }
        #endif
        isPlus = active
    }
}
