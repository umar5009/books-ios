import Foundation
import ARKit
import UIKit
import Combine

/// One front-camera pipeline for everything hands-free:
///  • ARKit face tracking (TrueDepth) → eye gaze point on screen, blinks, facial expression
///  • the same camera frames → Vision hand-pose → air-zoom gestures
/// All processing is on-device; frames are never stored.
@MainActor
final class SensorHub: NSObject, ObservableObject {
    static let shared = SensorHub()

    @Published private(set) var isSupported = ARFaceTrackingConfiguration.isSupported
    @Published private(set) var isRunning = false
    @Published private(set) var faceVisible = false
    @Published private(set) var gaze: CGPoint?                 // screen coordinates (points)
    @Published private(set) var expression = FaceExpression()
    @Published private(set) var hand = AirZoomDetector.HandState()
    @Published private(set) var calibration: GazeCalibration

    /// Fired on deliberate double-blink (two quick blinks within 0.7 s).
    let doubleBlink = PassthroughSubject<Void, Never>()
    /// Fired on air pinch / spread.
    let airZoom = PassthroughSubject<AirZoomDetector.Direction, Never>()

    var gestureDetectionEnabled = true

    private let session = ARSession()
    private let airZoomDetector = AirZoomDetector()
    private var fx = OneEuroFilter(minCutoff: 0.8, beta: 0.015)
    private var fy = OneEuroFilter(minCutoff: 0.8, beta: 0.015)
    private var users = 0

    // Blink state
    private var eyesClosedSince: TimeInterval?
    private var lastBlinkEnd: TimeInterval = 0

    // Calibration capture
    private var captureTarget: CGPoint?
    private var captured: [(features: [Double], target: CGPoint)] = []
    private(set) var lastFeatures: [Double]?

    private static let calibrationKey = "gazeCalibration.v1"

    var screenSize: CGSize {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size
            ?? CGSize(width: 390, height: 844)
    }

    override init() {
        if let d = UserDefaults.standard.data(forKey: Self.calibrationKey),
           let c = try? JSONDecoder().decode(GazeCalibration.self, from: d) {
            calibration = c
        } else {
            calibration = .uncalibrated(screen: CGSize(width: 390, height: 844))
        }
        super.init()
        session.delegate = self
        airZoomDetector.onZoom = { [weak self] d in self?.airZoom.send(d) }
        airZoomDetector.onHandState = { [weak self] s in self?.hand = s }
        if !calibration.isCalibrated { calibration = .uncalibrated(screen: screenSize) }
    }

    // MARK: Lifecycle (reference counted so several screens can share the camera)

    func start() {
        users += 1
        guard isSupported, !isRunning else { return }
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = false
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0, isRunning else { return }
        session.pause()
        isRunning = false
        gaze = nil
        faceVisible = false
    }

    // MARK: Calibration

    func beginCapture(target: CGPoint) { captureTarget = target }
    func endCapture() { captureTarget = nil }
    func resetCalibrationSamples() { captured = [] }

    @discardableResult
    func finishCalibration() -> GazeCalibration? {
        guard let cal = GazeCalibration.fit(samples: captured) else { return nil }
        calibration = cal
        fx.reset(); fy.reset()
        if let d = try? JSONEncoder().encode(cal) { UserDefaults.standard.set(d, forKey: Self.calibrationKey) }
        return cal
    }

    // MARK: Frame processing

    fileprivate func process(face: ARFaceAnchor, camera: ARCamera, time: TimeInterval) {
        faceVisible = face.isTracked
        guard face.isTracked else { gaze = nil; return }
        let b = face.blendShapes
        func v(_ k: ARFaceAnchor.BlendShapeLocation) -> Double { b[k]?.doubleValue ?? 0 }

        // Expression (smoothed) — feeds the mood engine.
        let e = FaceExpression(
            smile: (v(.mouthSmileLeft) + v(.mouthSmileRight)) / 2,
            frown: (v(.mouthFrownLeft) + v(.mouthFrownRight)) / 2,
            browDown: (v(.browDownLeft) + v(.browDownRight)) / 2,
            eyesHalfClosed: (v(.eyeSquintLeft) + v(.eyeSquintRight)) / 2 * 0.5 + (v(.eyeBlinkLeft) + v(.eyeBlinkRight)) / 4)
        expression = FaceExpression(smile: expression.smile * 0.9 + e.smile * 0.1,
                                    frown: expression.frown * 0.9 + e.frown * 0.1,
                                    browDown: expression.browDown * 0.9 + e.browDown * 0.1,
                                    eyesHalfClosed: expression.eyesHalfClosed * 0.95 + e.eyesHalfClosed * 0.05)

        // Blink detection (eyelids) — double blink = page turn.
        let blink = min(v(.eyeBlinkLeft), v(.eyeBlinkRight))
        if blink > 0.6 {
            if eyesClosedSince == nil { eyesClosedSince = time }
            return // gaze is unreliable while eyes are closed
        } else if blink < 0.3, let closed = eyesClosedSince {
            eyesClosedSince = nil
            let dur = time - closed
            if dur > 0.04 && dur < 0.45 {
                if time - lastBlinkEnd < 0.7 { doubleBlink.send(); lastBlinkEnd = 0 } else { lastBlinkEnd = time }
            }
        }

        // Gaze features: eye look-at direction + head pose relative to the camera.
        let rel = simd_mul(camera.transform.inverse, face.transform)
        let fwd = rel.columns.2
        let yaw = Double(atan2(fwd.x, fwd.z))
        let pitch = Double(asin(max(-1, min(1, -fwd.y))))
        let look = face.lookAtPoint
        let features: [Double] = [Double(look.x), Double(look.y), yaw, pitch,
                                  Double(rel.columns.3.x), Double(rel.columns.3.y), 1]
        lastFeatures = features
        if let t = captureTarget { captured.append((features, t)) }

        let raw = calibration.predict(features)
        let size = screenSize
        let x = min(max(0, fx.filter(Double(raw.x), t: time)), Double(size.width))
        let y = min(max(0, fy.filter(Double(raw.y), t: time)), Double(size.height))
        gaze = CGPoint(x: x, y: y)
    }

    fileprivate func process(pixelBuffer: CVPixelBuffer, time: TimeInterval) {
        guard gestureDetectionEnabled else { return }
        airZoomDetector.process(pixelBuffer, timestamp: time)
    }
}

extension SensorHub: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Pull out only what we need so the ARFrame itself is released promptly.
        let face = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
        let camera = frame.camera
        let time = frame.timestamp
        let buffer = frame.capturedImage
        MainActor.assumeIsolated {
            if let face { self.process(face: face, camera: camera, time: time) } else { self.faceVisible = false; self.gaze = nil }
            self.process(pixelBuffer: buffer, time: time)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.isRunning = false }
    }
}
