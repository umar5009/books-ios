import Foundation
import CoreGraphics

struct FaceExpression: Equatable {
    var smile: Double = 0
    var frown: Double = 0
    var browDown: Double = 0
    var eyesHalfClosed: Double = 0
}

/// 1€ filter — the standard low-latency jitter filter for gaze / pointer signals.
struct OneEuroFilter {
    var minCutoff: Double = 1.0
    var beta: Double = 0.02
    var dCutoff: Double = 1.0
    private var xPrev: Double?
    private var dxPrev: Double = 0
    private var tPrev: TimeInterval?

    init(minCutoff: Double = 1.0, beta: Double = 0.02) { self.minCutoff = minCutoff; self.beta = beta }

    private func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    mutating func filter(_ x: Double, t: TimeInterval) -> Double {
        guard let xp = xPrev, let tp = tPrev, t > tp else { xPrev = x; tPrev = t; return x }
        let dt = t - tp
        let dx = (x - xp) / dt
        let aD = alpha(dCutoff, dt)
        let dxHat = aD * dx + (1 - aD) * dxPrev
        let cutoff = minCutoff + beta * abs(dxHat)
        let a = alpha(cutoff, dt)
        let xHat = a * x + (1 - a) * xp
        xPrev = xHat; dxPrev = dxHat; tPrev = t
        return xHat
    }

    mutating func reset() { xPrev = nil; tPrev = nil; dxPrev = 0 }
}

/// Per-user gaze calibration: ridge regression from ARKit eye/head features to screen points.
/// Learns from ~9 targets × ~30 frames, which absorbs every device/face/geometry difference.
struct GazeCalibration: Codable {
    static let featureCount = 7
    var wx: [Double]
    var wy: [Double]
    var meanErrorPoints: Double?

    var isCalibrated: Bool { meanErrorPoints != nil }

    /// Rough default so the dot moves before calibration.
    static func uncalibrated(screen: CGSize) -> GazeCalibration {
        let w = Double(screen.width), h = Double(screen.height)
        // features: [lookX, lookY, yaw, pitch, headX, headY, 1]
        return GazeCalibration(wx: [-w * 4, 0, -w * 1.2, 0, 0, 0, w / 2],
                               wy: [0, -h * 3, 0, -h * 1.5, 0, 0, h / 2],
                               meanErrorPoints: nil)
    }

    func predict(_ f: [Double]) -> CGPoint {
        var x = 0.0, y = 0.0
        for i in 0..<min(f.count, wx.count) { x += wx[i] * f[i]; y += wy[i] * f[i] }
        return CGPoint(x: x, y: y)
    }

    static func fit(samples: [(features: [Double], target: CGPoint)], lambda: Double = 1e-4) -> GazeCalibration? {
        let n = featureCount
        guard samples.count >= n * 3 else { return nil }
        var xtx = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var xty = Array(repeating: 0.0, count: n), xtyY = Array(repeating: 0.0, count: n)
        for s in samples {
            for i in 0..<n {
                xty[i] += s.features[i] * Double(s.target.x)
                xtyY[i] += s.features[i] * Double(s.target.y)
                for j in 0..<n { xtx[i][j] += s.features[i] * s.features[j] }
            }
        }
        for i in 0..<(n - 1) { xtx[i][i] += lambda * Double(samples.count) } // don't regularise bias
        guard let wx = solve(xtx, xty), let wy = solve(xtx, xtyY) else { return nil }
        var cal = GazeCalibration(wx: wx, wy: wy, meanErrorPoints: 0)
        let err = samples.map { s -> Double in
            let p = cal.predict(s.features)
            return hypot(Double(p.x - s.target.x), Double(p.y - s.target.y))
        }
        cal.meanErrorPoints = err.reduce(0, +) / Double(err.count)
        return cal
    }

    /// Gaussian elimination with partial pivoting.
    private static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var m = a, v = b
        for c in 0..<n {
            guard let p = (c..<n).max(by: { abs(m[$0][c]) < abs(m[$1][c]) }), abs(m[p][c]) > 1e-12 else { return nil }
            m.swapAt(c, p); v.swapAt(c, p)
            for r in (c + 1)..<n {
                let f = m[r][c] / m[c][c]
                for k in c..<n { m[r][k] -= f * m[c][k] }
                v[r] -= f * v[c]
            }
        }
        var x = Array(repeating: 0.0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = v[r]
            for k in (r + 1)..<n { s -= m[r][k] * x[k] }
            x[r] = s / m[r][r]
        }
        return x
    }
}
