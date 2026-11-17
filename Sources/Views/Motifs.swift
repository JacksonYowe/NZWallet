// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Original mark: the four stars of the Southern Cross as they appear on the
/// New Zealand flag. Used instead of any official government logo, and not the
/// silver fern (the FernMark is a protected trademark).
private enum SouthernCross {
    // (x, y, outer radius) in unit coordinates
    static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.52, 0.13, 0.12), (0.20, 0.47, 0.12), (0.82, 0.40, 0.10), (0.50, 0.85, 0.14),
    ]

    static func star(_ i: Int, in r: CGRect, scale: CGFloat = 1) -> Path {
        let (x, y, rad) = stars[i]
        let c = CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
        let outer = min(r.width, r.height) * rad * scale, inner = outer * 0.42
        var p = Path()
        for k in 0..<10 {
            let a = Double(k) * .pi / 5 - .pi / 2
            let rr = k % 2 == 0 ? outer : inner
            let pt = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// All four stars as one shape (for strokes, masks and the holographic foil).
struct NZMarkShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in SouthernCross.stars.indices { p.addPath(SouthernCross.star(i, in: r)) }
        return p
    }
}

/// Filled Southern Cross with a thin outline, as on the flag.
struct NZMark: View {
    var color: Color = .nzAccent
    var outline: Color = .white
    var lineWidth: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(SouthernCross.stars.indices, id: \.self) { i in
                StarShape(index: i, scale: 1).stroke(outline, lineWidth: lineWidth * 2)
                StarShape(index: i, scale: 1).fill(color)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StarShape: Shape {
    let index: Int
    let scale: CGFloat
    func path(in r: CGRect) -> Path { SouthernCross.star(index, in: r, scale: scale) }
}

/// Original guilloche rosette (generated curves, as on banknotes and ID cards).
struct GuillocheRosette: Shape {
    var center = UnitPoint(x: 0.8, y: 0.55)
    var radius: CGFloat = 0.6          // as a fraction of the rect height

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.minX + rect.width * center.x, y: rect.minY + rect.height * center.y)
        let R = rect.height * radius
        // Three bands of interleaved rose curves
        let bands: [(base: CGFloat, amp: CGFloat, petals: Double, copies: Int)] = [
            (0.86, 0.12, 18, 6), (0.55, 0.16, 12, 5), (0.26, 0.10, 8, 4),
        ]
        for b in bands {
            for k in 0..<b.copies {
                let phase = Double(k) * .pi / Double(b.copies) / b.petals * 2
                for i in 0...720 {
                    let t = Double(i) / 720 * 2 * .pi
                    let r = R * (b.base + b.amp * CGFloat(sin(b.petals * t + phase * b.petals)))
                    let pt = CGPoint(x: c.x + r * CGFloat(cos(t)), y: c.y + r * CGFloat(sin(t)))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
            }
        }
        for f in [0.98, 1.0, 0.40, 0.42] as [CGFloat] {
            p.addEllipse(in: CGRect(x: c.x - R * f, y: c.y - R * f, width: 2 * R * f, height: 2 * R * f))
        }
        return p
    }
}

/// Fine wavy background lines, as on banknotes and ID cards.
struct SecurityWaves: Shape {
    var rows = 22
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for k in 0..<rows {
            let y0 = rect.minY + rect.height * (CGFloat(k) + 0.5) / CGFloat(rows)
            var x = rect.minX
            p.move(to: CGPoint(x: x, y: y0 + 2.5 * sin(x / 12 + CGFloat(k))))
            while x < rect.maxX {
                x += 4
                p.addLine(to: CGPoint(x: x, y: y0 + 2.5 * sin(x / 12 + CGFloat(k))))
            }
        }
        return p
    }
}

/// Neutral ID-photo placeholder (no real person).
struct PlaceholderPortrait: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let tone = Color(red: 0.47, green: 0.53, blue: 0.61)
            ZStack {
                LinearGradient(colors: [Color(red: 0.88, green: 0.91, blue: 0.95), Color(red: 0.78, green: 0.83, blue: 0.90)],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(tone).frame(width: w * 0.44, height: w * 0.44).position(x: w / 2, y: h * 0.37)
                Ellipse().fill(tone).frame(width: w * 0.92, height: h * 0.5).position(x: w / 2, y: h * 0.98)
            }
        }
        .clipped()
        .accessibilityLabel("Photo")
    }
}

struct SpecimenWatermark: View {
    var size: CGFloat = 42
    var body: some View {
        Text(verbatim: "TEST · WHAKAMĀTAU")
            .font(.gov(size: size, weight: .black))
            .foregroundStyle(Color.nzAccent.opacity(0.08))
            .rotationEffect(.degrees(-24))
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Original vector illustration of a kōwhai sprig: hanging yellow trumpet
/// flowers and stems. Kept native so the handoff needs no new bitmap.
struct KowhaiFlower: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Stem and hanging flower stems.
        p.move(to: CGPoint(x: 0.50, y: 0.04))
        p.addQuadCurve(to: CGPoint(x: 0.48, y: 0.85), control: CGPoint(x: 0.68, y: 0.43))
        for (x, y, direction) in [(0.48, 0.18, -1.0), (0.56, 0.39, 1.0), (0.48, 0.59, -1.0)] {
            p.move(to: CGPoint(x: 0.54, y: y - 0.06))
            p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x, y: y - 0.05))
            var bell = Path()
            bell.move(to: .zero)
            bell.addCurve(to: CGPoint(x: -0.04, y: 0.25),
                          control1: CGPoint(x: -0.065, y: 0.08),
                          control2: CGPoint(x: -0.075, y: 0.20))
            bell.addCurve(to: CGPoint(x: 0.09, y: 0.30),
                          control1: CGPoint(x: -0.045, y: 0.32),
                          control2: CGPoint(x: 0.045, y: 0.35))
            bell.addQuadCurve(to: CGPoint(x: 0.18, y: 0.24), control: CGPoint(x: 0.15, y: 0.31))
            bell.addQuadCurve(to: CGPoint(x: 0.105, y: 0.21), control: CGPoint(x: 0.12, y: 0.275))
            bell.addCurve(to: .zero,
                          control1: CGPoint(x: 0.055, y: 0.17),
                          control2: CGPoint(x: 0.06, y: 0.05))
            bell.closeSubpath()
            p.addPath(bell, transform: CGAffineTransform(scaleX: direction, y: 1)
                .concatenating(CGAffineTransform(translationX: x, y: y)))
        }
        let side = min(rect.width, rect.height)
        return p.applying(CGAffineTransform(scaleX: side, y: side)
            .concatenating(CGAffineTransform(translationX: rect.midX - side / 2,
                                            y: rect.midY - side / 2)))
    }
}

/// Continuous ordered fades. Tapping restarts the cycle. This button is never
/// nested inside a navigation control; the rest of the card navigates separately.
private struct AnimatedCardStars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var epoch = Date()

    var body: some View {
        Button {
            epoch = Date()
        } label: {
            TimelineView(.periodic(from: epoch, by: 1.0 / 30)) { context in
                ZStack {
                    ForEach(0..<4) { index in
                        let fade = CardStarCycle.opacity(index: index, elapsed: context.date.timeIntervalSince(epoch))
                        // Gentle colour/opacity changes remain active with Reduce Motion;
                        // no translation, scaling or rotation is used in either mode.
                        let opacity = reduceMotion ? 0.35 + fade * 0.65 : fade
                        StarShape(index: index, scale: 1)
                            .fill(Color.nzAccent)
                            .overlay(StarShape(index: index, scale: 1).stroke(Color.white, lineWidth: 0.7))
                            .opacity(opacity)
                    }
                }
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Restart Southern Cross star animation")
        .accessibilityIdentifier("licence.starAnimation")
        .onAppear { epoch = Date() }

    }
}

/// Dark band at the top of the card with the Southern Cross and bilingual title.
struct NZCardHeader: View {
    var compact = false
    var body: some View {
        HStack(spacing: 10) {
            AnimatedCardStars()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "AOTEAROA NEW ZEALAND")
                    .font(.gov(size: compact ? 10 : 11, weight: .heavy)).tracking(1.2)
                Text(verbatim: "Raihana Taraiwa · Driver Licence")
                    .font(.gov(size: compact ? 8 : 9, weight: .semibold))
                    .foregroundStyle(Color.nzSilver)
            }
            Spacer(minLength: 0)

        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 7 : 9)
        .background(Color.nzInk)
    }
}
