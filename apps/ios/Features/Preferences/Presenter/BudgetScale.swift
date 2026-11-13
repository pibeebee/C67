import Foundation

/// Q6 budget slider range, in Indonesian rupiah.
///
/// The Sketch frame shows Rp50.000 at the minimum and nine slider steps. The maximum is an
/// assumption until the product defines it.
enum BudgetScale {
    static let minimum: Double = 50_000
    static let maximum: Double = 500_000
    static let step: Double = 50_000
    static let range: ClosedRange<Double> = minimum ... maximum
    static let currency = FloatingPointFormatStyle<Double>.Currency(code: "IDR")

    /// Keeps a value inside the range and on a step.
    static func normalized(_ value: Double) -> Double {
        let clamped = min(max(value, minimum), maximum)
        return minimum + ((clamped - minimum) / step).rounded() * step
    }
}
