import Foundation
import Vision
import CoreVideo

/// Touch-free font zoom. Hold a hand in front of the phone (≈20–50 cm) and
/// spread thumb + index finger apart → bigger text, pinch them together → smaller text.
///
/// Uses Apple's on-device hand-pose neural network (VNDetectHumanHandPoseRequest, 21 joints).
/// The finger gap is normalised by palm size, so moving the hand closer/further doesn't trigger zoom.
final class AirZoomDetector {
    enum Direction { case zoomIn, zoomOut }

    struct HandState { var visible = false; var aperture: Double = 0; var baseline: Double = 0 }

    var onZoom: ((Direction) -> Void)?
    var onHandState: ((HandState) -> Void)?

    private let queue = DispatchQueue(label: "lumaread.hands", qos: .userInitiated)
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()
    private let lock = NSLock()
    private var busy = false
    private var lastRun: TimeInterval = 0

    // Gesture state (touched only on `queue`)
    private var baseline: Double?
    private var smoothed: Double?
    private var lastSeen: TimeInterval = 0
    private var lastEmit: TimeInterval = 0

    /// Call with every camera frame; internally throttled to ~10 fps, one frame in flight.
    func process(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        lock.lock()
        if busy || timestamp - lastRun < 0.1 { lock.unlock(); return }
        busy = true; lastRun = timestamp
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.lock(); self.busy = false; self.lock.unlock() }
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
            do {
                try handler.perform([self.request])
                self.handle(self.request.results?.first, size: CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                                                     height: CVPixelBufferGetHeight(pixelBuffer)),
                            t: timestamp)
            } catch { }
        }
    }

    private func handle(_ obs: VNHumanHandPoseObservation?, size: CGSize, t: TimeInterval) {
        guard let obs,
              let thumb = try? obs.recognizedPoint(.thumbTip), thumb.confidence > 0.5,
              let index = try? obs.recognizedPoint(.indexTip), index.confidence > 0.5,
              let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence > 0.4,
              let mcp = try? obs.recognizedPoint(.middleMCP), mcp.confidence > 0.4
        else {
            if t - lastSeen > 0.7 { baseline = nil; smoothed = nil }
            report(HandState(visible: false))
            return
        }
        lastSeen = t
        func px(_ p: VNRecognizedPoint) -> CGPoint { CGPoint(x: p.location.x * size.width, y: p.location.y * size.height) }
        let gap = hypot(px(thumb).x - px(index).x, px(thumb).y - px(index).y)
        let palm = max(1, hypot(px(wrist).x - px(mcp).x, px(wrist).y - px(mcp).y))
        let raw = Double(gap / palm)

        let s = (smoothed ?? raw) * 0.6 + raw * 0.4
        smoothed = s
        guard let base = baseline else { baseline = s; report(HandState(visible: true, aperture: s, baseline: s)); return }
        report(HandState(visible: true, aperture: s, baseline: base))

        guard t - lastEmit > 0.45 else { return }
        let ratio = s / max(0.05, base)
        if ratio > 1.55 && s > 0.45 {
            lastEmit = t; baseline = s; emit(.zoomIn)
        } else if ratio < 0.6 {
            lastEmit = t; baseline = s; emit(.zoomOut)
        } else {
            // Slow drift so a hand held still re-centres.
            baseline = base * 0.97 + s * 0.03
        }
    }

    private func emit(_ d: Direction) { DispatchQueue.main.async { self.onZoom?(d) } }
    private func report(_ s: HandState) { DispatchQueue.main.async { self.onHandState?(s) } }
}
