import SwiftUI

struct TripEmptyView: View {
    var planTrip: () -> Void = {}
    @State private var planTripTaps = 0

    var body: some View {
        VStack(spacing: 28) {
            TripPlanetIllustration()
                .frame(width: 240, height: 240)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Haven’t checked out any cool spots yet?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Let’s plan your next trip!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("homeEmptyState")
            Button {
                planTripTaps += 1
                planTrip()
            } label: {
                Label("Plan a Trip", systemImage: "plus")
            }
            .buttonStyle(PressableCapsuleButtonStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: planTripTaps)
            .accessibilityIdentifier("homePlanTrip")
        }
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
    }
}

#Preview {
    TripEmptyView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("TripCanvas"))
}

// MARK: - Planet illustration

/// Vector rebuild of the "planet with pins and magnifier" empty-state art, drawn on a 336-point grid
/// so each element can move on its own.
///
/// Motion: the scene assembles on appear (planet, orbit, pins dropping in, magnifier), then idles with
/// the magnifier scanning, a bounce passing across the pins, a satellite circling and sparkles twinkling.
/// Reduce Motion shows the finished, still composition.
struct TripPlanetIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var appearedAt = Date.distantFuture

    private static let grid: CGFloat = 336
    private let planetCenter = CGPoint(x: 172, y: 170)
    private let orbitCenter = CGPoint(x: 171, y: 158)
    private let orbitRadii = CGSize(width: 111, height: 34)
    private let orbitTilt = Angle.degrees(14)
    private let pins: [(tip: CGPoint, delay: Double)] = [
        (CGPoint(x: 116, y: 158), 0.0), (CGPoint(x: 211, y: 128), 0.18), (CGPoint(x: 237, y: 178), 0.36),
    ]

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / Self.grid
            Group {
                if reduceMotion {
                    scene(time: 0, isStill: true)
                } else {
                    TimelineView(.animation) { context in
                        scene(time: context.date.timeIntervalSinceReferenceDate, isStill: false)
                    }
                }
            }
            .frame(width: Self.grid, height: Self.grid)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            appeared = true
            appearedAt = .now
        }
    }

    // MARK: Scene

    private func scene(time t: Double, isStill: Bool) -> some View {
        let assembling = !isStill
        let shown = appeared || isStill
        return ZStack(alignment: .topLeading) {
            sparkles(time: t, isStill: isStill)
            orbitHalf(back: true, drawn: assembling ? (shown ? 1 : 0) : 1)
            if !isStill { satellite(time: t, back: true) }
            planet
                .scaleEffect(assembling ? (shown ? 1 : 0.6) : 1, anchor: .center)
                .opacity(assembling ? (shown ? 1 : 0) : 1)
                .animation(.spring(duration: 0.7, bounce: 0.3), value: shown)
            orbitHalf(back: false, drawn: assembling ? (shown ? 1 : 0) : 1)
            if !isStill { satellite(time: t, back: false) }
            ForEach(pins.indices, id: \.self) { index in
                pin(index: index, time: t, isStill: isStill, shown: shown)
            }
            magnifier(time: t, isStill: isStill, shown: shown)
        }
        .frame(width: Self.grid, height: Self.grid, alignment: .topLeading)
    }

    private var planet: some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(Color(uiColor: .systemGray5))
                .frame(width: 176, height: 176)
                .position(planetCenter)
            ForEach([CGPoint(x: 116, y: 156), CGPoint(x: 172, y: 167), CGPoint(x: 120, y: 207),
                     CGPoint(x: 211, y: 128), CGPoint(x: 235, y: 177), CGPoint(x: 197, y: 229)], id: \.x) { crater in
                Circle().fill(Color(uiColor: .systemGray4)).frame(width: 14, height: 14).position(crater)
            }
        }
        .frame(width: Self.grid, height: Self.grid, alignment: .topLeading)
    }

    /// The back half passes behind the planet, the front half in front of it.
    private func orbitHalf(back: Bool, drawn: CGFloat) -> some View {
        Ellipse()
            .trim(from: back ? 0.5 : 0, to: back ? 0.5 + 0.5 * drawn : 0.5 * drawn)
            .stroke(Color.primary.opacity(0.78), style: .init(lineWidth: 3, lineCap: .round))
            .frame(width: orbitRadii.width * 2, height: orbitRadii.height * 2)
            .rotationEffect(orbitTilt)
            .position(orbitCenter)
            .animation(.easeOut(duration: 0.9).delay(back ? 0.55 : 0.25), value: drawn)
    }

    private func orbitPoint(_ angle: Double) -> CGPoint {
        let x = orbitRadii.width * cos(angle), y = orbitRadii.height * sin(angle)
        let tilt = orbitTilt.radians
        return CGPoint(x: orbitCenter.x + x * cos(tilt) - y * sin(tilt), y: orbitCenter.y + x * sin(tilt) + y * cos(tilt))
    }

    @ViewBuilder private func satellite(time t: Double, back: Bool) -> some View {
        let angle = (t * 0.9).truncatingRemainder(dividingBy: 2 * .pi)
        let isBack = sin(angle) < 0
        // Fades in once the orbit has been drawn (about 1.4 s after appearing).
        let fade = min(max((t - appearedAt.timeIntervalSinceReferenceDate - 1.4) / 0.4, 0), 1)
        if isBack == back, fade > 0 {
            Circle().fill(AppColor.brand)
                .frame(width: 12, height: 12)
                .scaleEffect(isBack ? 0.75 : 1.1)
                .opacity((isBack ? 0.55 : 1) * fade)
                .position(orbitPoint(angle))
        }
    }

    private func pin(index: Int, time t: Double, isStill: Bool, shown: Bool) -> some View {
        let spec = pins[index]
        var lift: CGFloat = 0
        var squash: CGFloat = 1
        if !isStill {
            // A gentle float, plus a bounce that travels across the pins as if the magnifier just found each one.
            lift = 3 * sin(t * 1.5 + Double(index) * 1.1)
            let cycle = 3.6, phase = (t - spec.delay * 2).truncatingRemainder(dividingBy: cycle) / 0.5
            if phase >= 0, phase < 1 { lift += 12 * sin(phase * .pi); squash = 1 + 0.06 * sin(phase * .pi) }
        }
        let dropped = isStill || shown
        return PinShape()
            .fill(AppColor.brand)
            .overlay(alignment: .top) { Circle().fill(.white).frame(width: 11, height: 11).padding(.top, 8.5) }
            .frame(width: 28, height: 42)
            .scaleEffect(x: 1, y: squash, anchor: .bottom)
            .offset(y: -lift)
            .position(x: spec.tip.x, y: spec.tip.y - 21)
            .offset(y: dropped ? 0 : -140)
            .opacity(dropped ? 1 : 0)
            .animation(.spring(duration: 0.6, bounce: 0.5).delay(0.9 + spec.delay), value: dropped)
    }

    private func magnifier(time t: Double, isStill: Bool, shown: Bool) -> some View {
        // Small loop over the surface with a slight tilt, like scanning for places.
        let offset = isStill ? CGSize.zero : .init(width: 14 * cos(t * 1.75), height: 8 * sin(t * 1.75))
        let angle = Angle.degrees(isStill ? 0 : 6 * sin(t * 1.2))
        let arrived = isStill || shown
        return ZStack(alignment: .topLeading) {
            Capsule().fill(AppColor.brand)
                .frame(width: 46, height: 7)
                .rotationEffect(.degrees(41))
                .position(x: 234, y: 266)
            Circle().strokeBorder(AppColor.brand, lineWidth: 9)
                .frame(width: 52, height: 52)
                .position(x: 197, y: 232)
        }
        .frame(width: Self.grid, height: Self.grid, alignment: .topLeading)
        .rotationEffect(angle, anchor: UnitPoint(x: 197 / Self.grid, y: 232 / Self.grid))
        .offset(offset)
        .offset(x: arrived ? 0 : 90, y: arrived ? 0 : 90)
        .rotationEffect(arrived ? .zero : .degrees(-25), anchor: .bottomTrailing)
        .opacity(arrived ? 1 : 0)
        .animation(.spring(duration: 0.7, bounce: 0.35).delay(1.45), value: arrived)
    }

    private func sparkles(time t: Double, isStill: Bool) -> some View {
        let blue: [(CGPoint, CGFloat)] = [(.init(x: 177, y: 54), 5), (.init(x: 101, y: 88), 5), (.init(x: 61, y: 178), 7), (.init(x: 248, y: 246), 6)]
        let gray: [(CGPoint, CGFloat)] = [(.init(x: 148, y: 77), 4), (.init(x: 240, y: 73), 5), (.init(x: 278, y: 118), 7),
                                          (.init(x: 41, y: 110), 4), (.init(x: 292, y: 108), 3), (.init(x: 285, y: 159), 3)]
        func twinkle(_ i: Int) -> Double { isStill ? 1 : 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 2.2 + Double(i) * 1.7)) }
        return ZStack(alignment: .topLeading) {
            ForEach(blue.indices, id: \.self) { i in
                Circle().fill(AppColor.brand).frame(width: blue[i].1, height: blue[i].1)
                    .opacity(twinkle(i)).scaleEffect(twinkle(i)).position(blue[i].0)
            }
            ForEach(gray.indices, id: \.self) { i in
                Circle().fill(Color(uiColor: .systemGray3)).frame(width: gray[i].1, height: gray[i].1)
                    .opacity(twinkle(i + 4)).position(gray[i].0)
            }
            ForEach([CGPoint(x: 50, y: 149), CGPoint(x: 293, y: 207)], id: \.x) { point in
                Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(uiColor: .systemGray3))
                    .rotationEffect(.degrees(45 + (isStill ? 0 : t * 20)))
                    .position(point)
            }
        }
        .frame(width: Self.grid, height: Self.grid, alignment: .topLeading)
    }
}

/// Map pin silhouette: a circle tapering to a point at the bottom centre.
private struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + r)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: center.y),
                      control1: CGPoint(x: rect.midX - r * 0.35, y: rect.maxY - r * 0.55),
                      control2: CGPoint(x: rect.minX, y: center.y + r * 0.75))
        path.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: center.y + r * 0.75),
                      control2: CGPoint(x: rect.midX + r * 0.35, y: rect.maxY - r * 0.55))
        path.closeSubpath()
        return path
    }
}

/// Brand capsule that sinks slightly while pressed and springs back on release.
private struct PressableCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(AppColor.onBrand)
            .padding(.horizontal, 24)
            .frame(minHeight: 50)
            .background(AppColor.brand.opacity(isEnabled ? 1 : 0.4), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(configuration.isPressed ? .spring(duration: 0.18, bounce: 0) : .spring(duration: 0.4, bounce: 0.45),
                       value: configuration.isPressed)
            .contentShape(.capsule)
    }
}
