// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import CoreMotion

/// One sensor session shared by all visible foil layers. Polling also detects
/// stale data instead of assuming that sensor availability means data arrived.
@MainActor
final class TiltSensor: ObservableObject {
    static let shared = TiltSensor()
    @Published private(set) var x = 0.0
    @Published private(set) var y = 0.0
    @Published private(set) var unavailable = false
    private let motion = CMMotionManager()
    private var clients: Set<UUID> = []
    private var timer: Timer?
    private var neutral: CMAttitude?
    private var response = FoilTiltResponse()
    private var startedAt = Date()
    private var lastSampleAt = Date.distantPast
    private var lastTimestamp = -1.0

    func start(client: UUID) {
        clients.insert(client)
        guard timer == nil else { return }
        unavailable = false
        neutral = nil
        response = FoilTiltResponse()
        x = 0; y = 0
        startedAt = Date()
        lastSampleAt = .distantPast
        lastTimestamp = -1
        guard motion.isDeviceMotionAvailable else {
            #if !targetEnvironment(simulator)
            unavailable = true
            #endif
            return
        }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        let poller = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readSample() }
        }
        timer = poller
        RunLoop.main.add(poller, forMode: .common)
    }

    private func readSample() {
        let now = Date()
        if let sample = motion.deviceMotion, sample.timestamp != lastTimestamp {
            lastTimestamp = sample.timestamp
            lastSampleAt = now
            unavailable = false
            if neutral == nil { neutral = sample.attitude.copy() as? CMAttitude }
            if let reference = neutral, let relative = sample.attitude.copy() as? CMAttitude {
                relative.multiply(byInverseOf: reference)
                response.update(roll: relative.roll, pitch: relative.pitch)
                x = response.x; y = response.y
            }
        } else if now.timeIntervalSince(startedAt) > 2 && now.timeIntervalSince(lastSampleAt) > 1 {
            unavailable = true
            // Core Motion may stop during an interruption. Retry the actual feed.
            if !motion.isDeviceMotionActive {
                motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
                startedAt = now
            }
        }
    }

    func stop(client: UUID) {
        clients.remove(client)
        guard clients.isEmpty else { return }
        timer?.invalidate(); timer = nil
        motion.stopDeviceMotionUpdates()
        neutral = nil
    }
}

/// Explicit colour/gradient movement works independently of the Metal detail.
/// Reduce Motion disables parallax and automatic drift, but retains a direct
/// user-controlled colour response when the phone is tilted.
struct HologramFoil<S: Shape>: View {
    let shape: S
    var lineWidth: CGFloat = 1.2
    var filled = false
    var strength: Double = 0.55

    @ObservedObject private var tilt = TiltSensor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sensorClient = UUID()

    var body: some View {
        Group {
            #if targetEnvironment(simulator)
            if reduceMotion {
                foil(x: 0, y: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    foil(x: sin(t * 0.8) * 0.8, y: cos(t * 0.6) * 0.6)
                }
            }
            #else
            foil(x: tilt.x, y: tilt.y)
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { tilt.start(client: sensorClient) }
        .onDisappear { tilt.stop(client: sensorClient) }
    }

    @ViewBuilder private var base: some View {
        if filled { shape.fill(Color.white) } else { shape.stroke(Color.white, lineWidth: lineWidth) }
    }

    private func foil(x: Double, y: Double) -> some View {
        GeometryReader { geo in
            ZStack {
                base.colorEffect(ShaderLibrary.hologramFoil(.float2(geo.size), .float2(Float(x), Float(y))))
                LinearGradient(colors: [.cyan, .blue, .purple, .pink, .orange, .yellow, .mint],
                               startPoint: UnitPoint(x: -0.5 + x * 0.8, y: -0.3 + y * 0.5),
                               endPoint: UnitPoint(x: 1.4 + x * 0.8, y: 1.3 + y * 0.5))
                    .hueRotation(.degrees(x * 110 + y * 80))
                    .mask(base)
                    .opacity(0.8)
            }
            .offset(x: reduceMotion ? 0 : x * 12, y: reduceMotion ? 0 : y * 10)
        }
        .opacity(strength)
    }
}

struct TiltUnavailableNotice: View {
    @ObservedObject private var tilt = TiltSensor.shared
    var body: some View {
        if tilt.unavailable {
            GovNotice(text: "Tilt response is unavailable. Check motion access in Settings, then reopen the app.",
                      icon: "iphone.radiowaves.left.and.right", color: .orange)
        }
    }
}
