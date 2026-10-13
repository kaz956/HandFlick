import ARKit
import Foundation
import Observation
import simd

enum HandFlickState: String { case unavailable, idle, approaching, contact, cooldown }
struct HandJointSample { let timestamp: TimeInterval; let chirality: String; let joint: String; let worldTransform: simd_float4x4; let anchorTransform: simd_float4x4; let isTracked: Bool }

/// Public-API ARKit hand tracker. It keeps the latest left/right anchors on one update stream;
/// recognition is cancelled immediately whenever either required hand becomes unavailable.
@MainActor @Observable
final class HandTrackingManager {
    var leftAvailable = false; var rightAvailable = false; var state: HandFlickState = .unavailable
    var currentRegion: HandRegion?; var currentAction: FlickAction?; var contactDistance: Float = 0
    var statusMessage = "Hand tracking has not started."
    var latestLeft: HandAnchor?; var latestRight: HandAnchor?; var onPrimitive: ((HandFlickPrimitive, HandFlickMetadata) -> Void)?; var onTrackingChanged: ((Bool) -> Void)?; var onSample: ((HandJointSample, SIMD3<Float>?) -> Void)?; var onGeometry: ((HandGeometry, HandRegion?, HandFlickState) -> Void)?
    private var leftTimestamp: TimeInterval?; private var rightTimestamp: TimeInterval?
    private let provider = HandTrackingProvider(); private let session = ARKitSession(); private var recognizer = FlickRecognizer(config: HandFlickConfig())

    func start(config: HandFlickConfig) async {
        recognizer = FlickRecognizer(config: config)
        guard HandTrackingProvider.isSupported else { state = .unavailable; statusMessage = "Hand Tracking is unavailable on this device."; return }
        let authorization = await session.requestAuthorization(for: [.handTracking])
        guard authorization[.handTracking] == .allowed else {
            state = .unavailable
            statusMessage = "Hand Tracking permission was not granted. Enable it in Settings, then restart the trial."
            return
        }
        do {
            try await session.run([provider])
            statusMessage = "Waiting for both hands. Show left palm and right index finger to the headset."
            for await update in provider.anchorUpdates {
                let anchor = update.anchor
                if anchor.chirality == .left {
                    latestLeft = anchor; leftTimestamp = update.timestamp
                    // Keep the input-surface guide visible even before the right pointer appears.
                    if let geometry = HandGeometry(anchor: anchor) { onGeometry?(geometry, recognizer.region, recognizer.state) }
                } else { latestRight = anchor; rightTimestamp = update.timestamp }
                emitSamples(anchor: anchor, timestamp: update.timestamp)
                // Advance recognition once per pointer update.  The surface frame must be recent.
                if anchor.chirality == .right { process(timestamp: update.timestamp) }
            }
        } catch { state = .unavailable; statusMessage = "Could not start Hand Tracking: \(error.localizedDescription)" }
    }
    private func emitSamples(anchor: HandAnchor, timestamp: TimeInterval) {
        guard let skeleton = anchor.handSkeleton else { return }
        let leftGeometry = latestLeft.flatMap { HandGeometry(anchor: $0) }
        let names: [HandSkeleton.JointName] = [.wrist, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip]
        for name in names {
            let joint = skeleton.joint(name)
            let transform = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            onSample?(.init(timestamp: timestamp, chirality: anchor.chirality == .left ? "left" : "right", joint: String(describing: name), worldTransform: transform, anchorTransform: anchor.originFromAnchorTransform, isTracked: joint.isTracked), leftGeometry.map { $0.local(transform.translation) })
        }
    }
    func stop() { session.stop(); state = .unavailable; statusMessage = "Hand tracking stopped." }
    private func process(timestamp: TimeInterval) {
        let previous = leftAvailable && rightAvailable
        leftAvailable = latestLeft?.isTracked == true && latestLeft?.handSkeleton != nil
        rightAvailable = latestRight?.isTracked == true && latestRight?.handSkeleton != nil
        let available = leftAvailable && rightAvailable
        if previous != available { onTrackingChanged?(available) }
        if available { statusMessage = "Both hands are tracked." }
        guard available, let left = latestLeft, let right = latestRight, let leftTimestamp, let rightTimestamp, abs(leftTimestamp - rightTimestamp) <= recognizer.config.maximumFrameSkew, let rightSkeleton = right.handSkeleton else { recognizer.cancel(); state = .unavailable; statusMessage = "Waiting for synchronized left and right hand frames."; return }
        // Finger-on-finger contact may temporarily occlude an individual joint.  ARKit retains
        // a useful transform, so use anchor-level tracking and reject only invalid coordinates.
        let tip = rightSkeleton.joint(.indexFingerTip)
        let tipWorld = (right.originFromAnchorTransform * tip.anchorFromJointTransform).translation
        guard tipWorld.x.isFinite, tipWorld.y.isFinite, tipWorld.z.isFinite else { recognizer.cancel(); state = .unavailable; return }
        let geometry = HandGeometry(anchor: left)
        guard let result = recognizer.update(tipWorld: tipWorld, geometry: geometry, timestamp: timestamp) else { state = recognizer.state; currentRegion = recognizer.region; currentAction = recognizer.action; contactDistance = recognizer.distance; if let geometry { onGeometry?(geometry, recognizer.region, recognizer.state) }; return }
        state = recognizer.state; currentRegion = result.primitive.region; currentAction = result.primitive.action; contactDistance = result.distance
        if let geometry { onGeometry?(geometry, result.primitive.region, recognizer.state) }
        onPrimitive?(result.primitive, .init(contactStart: result.contactStarted, recognitionTime: Date(), contactDistance: result.distance, maximumDisplacement: result.maximumDisplacement, leftAvailable: leftAvailable, rightAvailable: rightAvailable))
    }
}

struct HandGeometry {
    let anchor: HandAnchor; let origin: SIMD3<Float>; let longitudinal: SIMD3<Float>; let lateral: SIMD3<Float>; let normal: SIMD3<Float>; let handWidth: Float; let segments: [(HandRegion, SIMD3<Float>, SIMD3<Float>)]
    init?(anchor: HandAnchor) {
        self.anchor = anchor
        guard let skeleton = anchor.handSkeleton else { return nil }
        func p(_ name: HandSkeleton.JointName) -> SIMD3<Float>? {
            let j = skeleton.joint(name)
            let point = (anchor.originFromAnchorTransform * j.anchorFromJointTransform).translation
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
            return point
        }
        guard let wristPoint = p(.wrist), let indexPoint = p(.indexFingerKnuckle), let littlePoint = p(.littleFingerKnuckle) else { return nil }
        origin = wristPoint; lateral = simd_normalize(indexPoint - littlePoint); longitudinal = simd_normalize((indexPoint + littlePoint) * 0.5 - wristPoint); normal = simd_normalize(simd_cross(longitudinal, lateral)); handWidth = max(0.001, simd_distance(indexPoint, littlePoint))
        let definitions: [(FingerID, SegmentID, HandSkeleton.JointName, HandSkeleton.JointName)] = [(.index,.proximal,.indexFingerKnuckle,.indexFingerIntermediateBase),(.index,.middle,.indexFingerIntermediateBase,.indexFingerIntermediateTip),(.index,.distal,.indexFingerIntermediateTip,.indexFingerTip),(.middle,.proximal,.middleFingerKnuckle,.middleFingerIntermediateBase),(.middle,.middle,.middleFingerIntermediateBase,.middleFingerIntermediateTip),(.middle,.distal,.middleFingerIntermediateTip,.middleFingerTip),(.ring,.proximal,.ringFingerKnuckle,.ringFingerIntermediateBase),(.ring,.middle,.ringFingerIntermediateBase,.ringFingerIntermediateTip),(.ring,.distal,.ringFingerIntermediateTip,.ringFingerTip),(.little,.proximal,.littleFingerKnuckle,.littleFingerIntermediateBase),(.little,.middle,.littleFingerIntermediateBase,.littleFingerIntermediateTip),(.little,.distal,.littleFingerIntermediateTip,.littleFingerTip)]
        segments = definitions.compactMap { finger, segment, a, b in guard let pa = p(a), let pb = p(b) else { return nil }; return (HandRegion(finger: finger, segment: segment), pa, pb) }
    }
    func local(_ world: SIMD3<Float>) -> SIMD3<Float> { let d = world - origin; return SIMD3(simd_dot(d, lateral), simd_dot(d, longitudinal), simd_dot(d, normal)) / handWidth }
    /// Exact signed distance to a finite cylinder with flat end caps, normalized by palm width.
    func signedDistance(to point: SIMD3<Float>, region: HandRegion, radius: Float, extensionAmount: Float = 0) -> Float? {
        guard let segment = segments.first(where: { $0.0 == region }) else { return nil }
        let axis = segment.2 - segment.1; let length = simd_length(axis); guard length > 0.0001 else { return nil }
        let unitAxis = axis / length; let fromStart = point - segment.1; let axial = simd_dot(fromStart, unitAxis)
        let radial = simd_length(fromStart - axial * unitAxis); let radiusMetres = radius * handWidth
        let radialOffset = radial - radiusMetres; let axialOffset = abs(axial - length * 0.5) - (length * 0.5 + extensionAmount * handWidth)
        return (sqrt(max(radialOffset, 0) * max(radialOffset, 0) + max(axialOffset, 0) * max(axialOffset, 0)) + min(max(radialOffset, axialOffset), 0)) / handWidth
    }
    func nearest(to point: SIMD3<Float>, radius: Float) -> (HandRegion, Float)? { segments.compactMap { segment in signedDistance(to: point, region: segment.0, radius: radius).map { (segment.0, $0) } }.min { $0.1 < $1.1 } }
}
private extension simd_float4x4 { var translation: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) } }

private struct FlickResult { let primitive: HandFlickPrimitive; let distance: Float; let maximumDisplacement: Float; let contactStarted: Date }
private final class FlickRecognizer {
    var config: HandFlickConfig; var state: HandFlickState = .idle; var region: HandRegion?; var action: FlickAction?; var distance: Float = 0
    private var startLocal: SIMD3<Float>?; private var maximumPlanarDelta = SIMD2<Float>(repeating: 0); private var maximumDisplacement: Float = 0; private var startedAt: TimeInterval = 0; private var cooldownUntil: TimeInterval = 0; private var candidate: HandRegion?; private var candidateFrames = 0; private var releaseFrames = 0; private var armed = false
    init(config: HandFlickConfig) { self.config = config }
    func cancel() { state = .unavailable; region = nil; startLocal = nil; candidate = nil; candidateFrames = 0; releaseFrames = 0; armed = false }
    func update(tipWorld: SIMD3<Float>, geometry: HandGeometry?, timestamp: TimeInterval) -> FlickResult? {
        guard let geometry, let nearest = geometry.nearest(to: tipWorld, radius: config.contactThreshold) else { cancel(); return nil }
        distance = nearest.1
        let outsideAll = (geometry.nearest(to: tipWorld, radius: config.releaseThreshold)?.1 ?? .infinity) > 0
        if outsideAll { armed = true }
        if timestamp < cooldownUntil { state = .cooldown; return nil }
        guard armed else { state = .idle; return nil }
        if let locked = region, let q0 = startLocal {
            let exitDistance = geometry.signedDistance(to: tipWorld, region: locked, radius: config.releaseThreshold, extensionAmount: config.releaseThreshold - config.contactThreshold) ?? .infinity
            let delta = geometry.local(tipWorld) - q0; let planar = SIMD2(delta.x, delta.y); let magnitude = simd_length(planar)
            if magnitude > maximumDisplacement { maximumDisplacement = magnitude; maximumPlanarDelta = planar }
            releaseFrames = exitDistance > 0 ? releaseFrames + 1 : 0
            if timestamp - startedAt > config.maximumContactDuration { finishCooldown(timestamp); return nil }
            guard releaseFrames >= config.stableReleaseFrames else { state = .contact; return nil }
            let recognized = classify(maximumPlanarDelta); let result = FlickResult(primitive: .init(region: locked, action: recognized), distance: distance, maximumDisplacement: maximumDisplacement, contactStarted: Date().addingTimeInterval(-(timestamp - startedAt)))
            action = recognized; finishCooldown(timestamp); return result
        }
        guard nearest.1 <= 0 else { candidate = nil; candidateFrames = 0; state = .idle; return nil }
        if candidate == nearest.0 { candidateFrames += 1 } else { candidate = nearest.0; candidateFrames = 1 }
        state = .approaching
        guard candidateFrames >= config.stableContactFrames else { return nil }
        region = nearest.0; startLocal = geometry.local(tipWorld); startedAt = timestamp; maximumDisplacement = 0; maximumPlanarDelta = .zero; releaseFrames = 0; candidate = nil; candidateFrames = 0; state = .contact; return nil
    }
    private func finishCooldown(_ timestamp: TimeInterval) { region = nil; startLocal = nil; armed = false; state = .cooldown; cooldownUntil = timestamp + config.cooldownDuration }
    private func classify(_ delta: SIMD2<Float>) -> FlickAction { guard maximumDisplacement >= config.flickDistanceThreshold else { return .center }; return abs(delta.y) >= abs(delta.x) ? (delta.y >= 0 ? .forward : .backward) : (delta.x >= 0 ? .radial : .ulnar) }
}
