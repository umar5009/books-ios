import SwiftUI

struct ReaderView: View {
    let book: Book
    @EnvironmentObject var sensors: SensorHub
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var recommender: RecommendationEngine
    @EnvironmentObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model: ReaderModel
    @State private var chrome = true
    @State private var textFrame: CGRect = .zero
    @State private var hud: String?
    @State private var showSettings = false
    @State private var showCalibration = false
    @State private var showPaywall = false
    @State private var handsFree = false

    init(book: Book) {
        self.book = book
        _model = StateObject(wrappedValue: ReaderModel(book: book, fontSize: CGFloat(AppSettings.shared.fontSize)))
    }

    private var theme: ReaderTheme { settings.readerTheme }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar.opacity(chrome ? 1 : 0)
                page
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                bottomBar.opacity(chrome ? 1 : 0)
            }

            if settings.showGazeDot, handsFree, let g = sensors.gaze {
                GeometryReader { _ in
                    Circle()
                        .fill(Theme.accent2.opacity(0.35))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Theme.accent2, lineWidth: 2))
                        .position(g)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            if let hud {
                Text(hud)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .transition(.scale.combined(with: .opacity))
            }

            if model.isLoading || (!model.isReady && model.errorMessage == nil) {
                VStack(spacing: 14) {
                    MoodOrb(size: 70)
                    Text("Preparing your book…").foregroundStyle(theme.text.opacity(0.7))
                }
            }
            if let err = model.errorMessage {
                ContentUnavailableView("Couldn't open book", systemImage: "wifi.exclamationmark", description: Text(err))
            }
        }
        .statusBarHidden(!chrome)
        .animation(.easeInOut(duration: 0.25), value: chrome)
        .task {
            await model.load(resumeAt: library.progress[book.id]?.charOffset ?? 0)
        }
        .onAppear {
            startHandsFreeIfAllowed()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            if handsFree { sensors.stop() }
            model.close(library: library, recommender: recommender)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(sensors.$gaze) { g in
            guard handsFree, settings.eyeTrackingEnabled else { return }
            model.updateGaze(g, in: textFrame, autoTurn: settings.autoPageTurn)
        }
        .onReceive(sensors.doubleBlink) { _ in
            guard handsFree, settings.doubleBlinkTurn else { return }
            model.nextPage()
        }
        .onReceive(sensors.airZoom) { dir in
            guard handsFree, settings.airZoomEnabled else { return }
            model.zoom(dir)
            settings.fontSize = Double(model.fontSize)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring) { hud = dir == .zoomIn ? "A+  \(Int(model.fontSize))" : "A−  \(Int(model.fontSize))" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { hud = nil } }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(model: model, handsFree: $handsFree,
                                onCalibrate: {
                                    showSettings = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showCalibration = true }
                                },
                                onToggleHandsFree: toggleHandsFree)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showCalibration) { CalibrationView() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: Page

    private var page: some View {
        GeometryReader { geo in
            let lines = model.pageLines
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    lineView(line, index: i)
                        .frame(height: model.lineHeight, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .id(model.pageIndex)
            .transition(.asymmetric(insertion: .move(edge: model.turnDirection).combined(with: .opacity),
                                    removal: .opacity))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -40 { model.nextPage() } else if v.translation.width > 40 { model.previousPage() }
            })
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                let x = tap.location.x / max(1, geo.size.width)
                if x < 0.28 { model.previousPage() } else if x > 0.72 { model.nextPage() } else { chrome.toggle() }
            })
            .onAppear { model.setSize(geo.size); textFrame = geo.frame(in: .global) }
            .onChange(of: geo.size) { _, s in model.setSize(s); textFrame = geo.frame(in: .global) }
            .onChange(of: chrome) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { textFrame = geo.frame(in: .global) }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: Paginator.Line, index: Int) -> some View {
        let isActive = handsFree && settings.eyeTrackingEnabled && model.activeLine == index
        Text(attributed(line.text, highlightWord: isActive && settings.wordHighlight ? model.activeWord : nil))
            .font(Font(model.uiFont))
            .foregroundStyle(theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? theme.lineHighlight : .clear)
                    .padding(.horizontal, -8)
                    .padding(.vertical, 2)
                    .animation(.easeOut(duration: 0.18), value: isActive)
            )
    }

    private func attributed(_ text: String, highlightWord: Int?) -> AttributedString {
        var s = AttributedString(text)
        guard let w = highlightWord else { return s }
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard w < words.count else { return s }
        let start = words[..<w].reduce(0) { $0 + $1.count + 1 }
        let len = words[w].count
        guard len > 0, start + len <= text.count else { return s }
        let lo = s.index(s.startIndex, offsetByCharacters: start)
        let hi = s.index(lo, offsetByCharacters: len)
        s[lo..<hi].backgroundColor = theme.wordHighlight
        return s
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: { Image(systemName: "chevron.down") }
            VStack(alignment: .leading, spacing: 0) {
                Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(book.authorLine).font(.caption2).opacity(0.6)
            }
            Spacer()
            Button(action: toggleHandsFree) {
                Image(systemName: handsFree ? "eye.fill" : "eye.slash")
                    .foregroundStyle(handsFree ? Theme.accent2 : theme.text)
            }
            Button { showSettings = true } label: { Image(systemName: "textformat.size") }
        }
        .font(.title3)
        .foregroundStyle(theme.text)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if handsFree { sensorStatus }
            HStack {
                Text("\(model.pageIndex + 1) / \(model.totalPages)\(model.isPaginating ? "+" : "")")
                Spacer()
                if model.endOfPageArmed {
                    Label("Turning…", systemImage: "arrow.turn.down.right").foregroundStyle(Theme.accent2)
                }
                Spacer()
                Text("\(Int(model.fraction * 100))%")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(theme.text.opacity(0.6))
            ProgressView(value: model.fraction).tint(Theme.accent)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var sensorStatus: some View {
        HStack(spacing: 8) {
            statusPill(sensors.faceVisible ? "Eyes tracked" : "Looking for you…",
                       "eye", on: sensors.faceVisible)
            if settings.airZoomEnabled {
                statusPill(sensors.hand.visible ? "Hand ready — spread / pinch" : "Air Zoom", "hand.raised.fingers.spread",
                           on: sensors.hand.visible)
            }
            if !sensors.calibration.isCalibrated {
                Button("Calibrate") { showCalibration = true }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.warm)
            }
        }
    }

    private func statusPill(_ text: String, _ symbol: String, on: Bool) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(on ? Theme.accent2.opacity(0.2) : Color.gray.opacity(0.18)))
            .foregroundStyle(on ? Theme.accent2 : theme.text.opacity(0.6))
    }

    // MARK: Hands-free

    private func startHandsFreeIfAllowed() {
        guard store.isPlus, sensors.isSupported, settings.eyeTrackingEnabled || settings.airZoomEnabled else { return }
        sensors.gestureDetectionEnabled = settings.airZoomEnabled
        sensors.start()
        handsFree = true
        if !sensors.calibration.isCalibrated && settings.eyeTrackingEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showCalibration = true }
        }
    }

    private func toggleHandsFree() {
        if handsFree {
            sensors.stop(); handsFree = false
        } else if !store.isPlus {
            showPaywall = true
        } else if !sensors.isSupported {
            hud = "Needs Face ID camera"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { hud = nil }
        } else {
            sensors.gestureDetectionEnabled = settings.airZoomEnabled
            sensors.start(); handsFree = true
        }
    }
}
