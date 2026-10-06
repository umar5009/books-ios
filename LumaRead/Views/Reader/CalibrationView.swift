import SwiftUI

/// 9-point gaze calibration (~15 s). Follow the dot with your eyes, keep your head relaxed.
struct CalibrationView: View {
    @EnvironmentObject var sensors: SensorHub
    @Environment(\.dismiss) private var dismiss

    @State private var step = -1          // -1 intro, 0..8 points, 9 done
    @State private var dotScale: CGFloat = 1
    @State private var result: GazeCalibration?
    @State private var failed = false

    private let grid: [CGPoint] = [
        CGPoint(x: 0.1, y: 0.12), CGPoint(x: 0.5, y: 0.12), CGPoint(x: 0.9, y: 0.12),
        CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.9, y: 0.5),
        CGPoint(x: 0.1, y: 0.88), CGPoint(x: 0.5, y: 0.88), CGPoint(x: 0.9, y: 0.88),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if step == -1 { intro }
                else if step < grid.count {
                    let p = CGPoint(x: grid[step].x * geo.size.width, y: grid[step].y * geo.size.height)
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.3)).frame(width: 60, height: 60).scaleEffect(dotScale)
                        Circle().fill(Theme.brandGradient).frame(width: 18, height: 18)
                    }
                    .position(p)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: step)
                    Text("Look at the dot · \(step + 1)/\(grid.count)")
                        .font(.footnote).foregroundStyle(.white.opacity(0.5))
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.31)
                } else { done }
            }
            .task(id: step) { await runStep(size: geo.size) }
        }
        .ignoresSafeArea()
        .onAppear { sensors.start() }
        .onDisappear { sensors.stop() }
    }

    private var intro: some View {
        VStack(spacing: 20) {
            Image(systemName: "eye.circle.fill").font(.system(size: 70)).foregroundStyle(Theme.brandGradient)
            Text("Teach LumaRead your eyes").font(.title2.bold()).foregroundStyle(.white)
            Text("Hold your phone like you normally read. Follow the glowing dot with your eyes only. Takes 15 seconds.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.dim).padding(.horizontal, 30)
            Label(sensors.faceVisible ? "Face found" : "Looking for your face…", systemImage: "faceid")
                .foregroundStyle(sensors.faceVisible ? Theme.accent2 : Theme.warm)
            Button("Start") { sensors.resetCalibrationSamples(); step = 0 }
                .buttonStyle(GradientButtonStyle()).padding(.horizontal, 60)
                .disabled(!sensors.faceVisible)
                .opacity(sensors.faceVisible ? 1 : 0.5)
            Button("Not now") { dismiss() }.foregroundStyle(Theme.dim)
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            Image(systemName: failed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 64)).foregroundStyle(failed ? AnyShapeStyle(Theme.warm) : AnyShapeStyle(Theme.brandGradient))
            Text(failed ? "Let's try that again" : "You're calibrated").font(.title2.bold()).foregroundStyle(.white)
            if let r = result, let e = r.meanErrorPoints {
                Text("Average accuracy ≈ \(Int(e)) pt. Line tracking works best below ~40 pt.")
                    .font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center).padding(.horizontal, 30)
            }
            Button(failed ? "Retry" : "Start reading") {
                if failed { failed = false; step = -1 } else { dismiss() }
            }
            .buttonStyle(GradientButtonStyle()).padding(.horizontal, 60)
        }
    }

    private func runStep(size: CGSize) async {
        guard step >= 0, step < grid.count else { return }
        let target = CGPoint(x: grid[step].x * size.width, y: grid[step].y * size.height)
        withAnimation(.easeInOut(duration: 0.6).repeatForever()) { dotScale = 1.6 }
        try? await Task.sleep(for: .milliseconds(650))     // let the eyes settle
        sensors.beginCapture(target: target)
        try? await Task.sleep(for: .milliseconds(1100))
        sensors.endCapture()
        dotScale = 1
        if step == grid.count - 1 {
            result = sensors.finishCalibration()
            failed = result == nil || (result?.meanErrorPoints ?? 999) > 120
        }
        step += 1
    }
}
