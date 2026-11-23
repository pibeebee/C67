import SwiftUI

/// Full-screen wait state used while finding places and organizing trips.
struct ProcessingStatusView<Illustration: View>: View {
    let title: Text
    let message: Text
    var spacing: CGFloat = 40
    @ViewBuilder let illustration: () -> Illustration

    @ScaledMetric(relativeTo: .title) private var statusHeight = 68.0

    var body: some View {
        ScrollView {
            VStack(spacing: spacing) {
                title
                    .font(AppFont.title1Bold)
                    .accessibilityAddTraits(.isHeader)
                illustration()
                    .frame(maxWidth: 364)
                    .frame(height: 239)
                    .accessibilityHidden(true)
                message
                    .contentTransition(.opacity)
                    .font(AppFont.title1)
                    .frame(minHeight: statusHeight, alignment: .top)
                    .frame(maxWidth: 320)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(AppColor.primaryText)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .background(AppColor.canvas.ignoresSafeArea())
    }
}

struct RecommendationProcessingIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Keep the first choice for this presentation, even when the status text changes.
    @State private var showsDrive = Bool.random()

    var body: some View {
        ZStack {
            if showsDrive {
                TripProcessingDrive(reduceMotion: reduceMotion)
            } else {
                TripProcessingGlobe(reduceMotion: reduceMotion)
            }
        }
    }
}

private struct TripProcessingDrive: View {
    let reduceMotion: Bool
    var car = "LunaProcessingDriveCar"

    var body: some View {
        if reduceMotion {
            TripProcessingDriveScene(turn: 0, car: car)
        } else {
            TripProcessingDriveScene(turn: 0, car: car)
                .keyframeAnimator(initialValue: 0.0, repeating: true) { _, turn in
                    TripProcessingDriveScene(turn: turn, car: car)
                } keyframes: { _ in
                    LinearKeyframe(1, duration: 6)
                }
        }
    }
}

/// The trip-planning wait scene: the blue convertible driving through the city, with rain
/// falling over it while the forecast is checked. Reduce Motion keeps the car and rain still.
struct TripPlanningDriveIllustration: View {
    var raining = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TripProcessingDrive(reduceMotion: reduceMotion, car: "TripProcessingDriveCarBlue")
            .overlay(alignment: .bottom) {
                // Rain starts well above the scene, as in the design, where it falls from the top of the screen.
                TripProcessingRain(reduceMotion: reduceMotion)
                    .padding(.top, -110)
                    .opacity(raining ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: raining)
                    .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }
}

/// Teardrops falling from above the scene onto the skyline, fading out above the road.
private struct TripProcessingRain: View {
    let reduceMotion: Bool
    private static let drops: [(x: Double, offset: Double, speed: Double, size: Double)] = (0 ..< 34).map { index in
        let seed = Double(index)
        return ((seed * 0.6180339).truncatingRemainder(dividingBy: 1),
                (seed * 0.3819660).truncatingRemainder(dividingBy: 1),
                0.85 + (seed * 0.7548776).truncatingRemainder(dividingBy: 1) * 0.4,
                0.7 + (seed * 0.5698403).truncatingRemainder(dividingBy: 1) * 0.5)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tick in
            let time = reduceMotion ? 0 : tick.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let color = Color(red: 0.42, green: 0.64, blue: 0.82)
                for drop in Self.drops {
                    let progress = (time * 0.45 * drop.speed + drop.offset).truncatingRemainder(dividingBy: 1)
                    let center = CGPoint(x: drop.x * size.width * 0.75 + size.width * 0.05,
                                         y: -10 + progress * size.height * 0.95)
                    let width = 5.5 * drop.size, height = 10 * drop.size
                    // A teardrop: round base, pointed top, tilted slightly with the wind.
                    var tear = Path()
                    tear.move(to: CGPoint(x: 0, y: -height / 2))
                    tear.addQuadCurve(to: CGPoint(x: width / 2, y: height * 0.18), control: CGPoint(x: width * 0.45, y: -height * 0.05))
                    tear.addArc(center: CGPoint(x: 0, y: height * 0.18), radius: width / 2,
                                startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                    tear.addQuadCurve(to: CGPoint(x: 0, y: -height / 2), control: CGPoint(x: -width * 0.45, y: -height * 0.05))
                    let placed = tear.applying(CGAffineTransform(rotationAngle: 0.18).concatenating(
                        CGAffineTransform(translationX: center.x, y: center.y)))
                    context.fill(placed, with: .color(color.opacity(0.9)))
                }
            }
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62),
                                   .init(color: .clear, location: 0.8)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct TripProcessingDriveScene: View {
    let turn: Double
    var car = "LunaProcessingDriveCar"

    var body: some View {
        Color.clear
            .aspectRatio(364.0 / 185, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let scale = geometry.size.width / 364
                    let angle = turn * 2 * .pi
                    let carOffset = sin(angle) * 4 * scale

                    ZStack {
                        skyline(size: geometry.size)
                        Image("LunaProcessingDriveClouds")
                            .resizable()
                            .offset(x: sin(angle) * 12 * scale)
                        Image("LunaProcessingDriveRoad").resizable()
                        Image(car)
                            .resizable()
                            .offset(x: carOffset, y: sin(angle * 3) * 1.5 * scale)

                        // Wheel centers are measured in the scene's SVG viewBox.
                        wheel(scale: scale)
                            .position(x: 109.30 * scale + carOffset, y: 145.36 * scale)
                        wheel(scale: scale)
                            .position(x: 267.45 * scale + carOffset, y: 145.97 * scale)
                    }
                }
            }
    }

    private func skyline(size: CGSize) -> some View {
        HStack(spacing: 0) {
            ForEach(0 ..< 2) { _ in
                Image("LunaProcessingDriveCity")
                    .resizable()
                    .frame(width: size.width, height: size.height)
            }
        }
        .fixedSize()
        .offset(x: -turn * size.width)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.10),
                    .init(color: .black, location: 0.90),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        // The artwork travels left regardless of the interface language.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func wheel(scale: CGFloat) -> some View {
        Image("LunaProcessingDriveWheel")
            .resizable()
            .frame(width: 44 * scale, height: 44 * scale)
            .rotationEffect(.degrees(turn * 5 * 360))
    }
}

private struct TripProcessingGlobe: View {
    let reduceMotion: Bool

    var body: some View {
        Circle()
            .fill(Color(red: 199.0 / 255, green: 229.0 / 255, blue: 240.0 / 255))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 239)
            .overlay {
                GeometryReader { geometry in
                    let scale = geometry.size.width / 239
                    let globeSize = 340 * scale
                    let globe = Image("LunaProcessingGlobe")
                        .resizable()
                        .frame(width: globeSize, height: globeSize)

                    Group {
                        if reduceMotion {
                            globe
                        } else {
                            globe.keyframeAnimator(initialValue: 0.0, repeating: true) { image, degrees in
                                image.rotationEffect(.degrees(degrees))
                            } keyframes: { _ in
                                LinearKeyframe(360, duration: 12)
                            }
                        }
                    }
                    // The original composition shows only the upper arc of the globe.
                    .position(x: geometry.size.width / 2, y: 223.113 * scale)
                }
            }
            .clipShape(Circle())
    }
}
