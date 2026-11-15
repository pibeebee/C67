import Foundation

/// Q7 "How are we getting around?" — how the traveller moves between stops.
enum TransportMode: String, CaseIterable, ChoiceOption, Sendable {
    case publicTransport
    case privateCar
    case motorcycle
    case anything

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .publicTransport: "Public Transportation"
        case .privateCar: "Private Car"
        case .motorcycle: "Motorcycle"
        case .anything: "Whatever works"
        }
    }
}
