import Foundation

/// Q5 "When do you prefer to explore?" — preferred part of the day.
enum DayPart: String, CaseIterable, ChoiceOption, Sendable {
    case morning
    case afternoon
    case evening
    case night

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .morning: "Morning (06:00 - 11:00)"
        case .afternoon: "Afternoon (11:00 - 15:00)"
        case .evening: "Evening (15:00 - 18:00)"
        case .night: "Night (18:00 - 22:00)"
        }
    }
}
