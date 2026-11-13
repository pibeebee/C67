import Foundation

@main struct InputChecks {
    static func main() throws {
        let zone = TimeZone(identifier: "Asia/Jakarta")!
        let now = Date(timeIntervalSince1970: 1_793_664_000)
        var draft = NativeTripDraft.empty(now: now, timeZone: zone)
        precondition(draft.stops.isEmpty && draft.origin.query.isEmpty && draft.end.query.isEmpty)
        precondition(draft.departure == now && draft.timeZoneID == zone.identifier)
        precondition(draft.searchContext.isEmpty && draft.origin.searchRegion == nil)
        print("PASS 1: empty trip contains no Japan fixture or implicit location")

        let input = " 1. Museum, Jakarta\r\n2) Café\n- 鎌倉駅\n* 123 Main Street\n• Museum, Jakarta\n\n  "
        let names = NativeTripListInput.names(from: input)
        precondition(names == ["Museum, Jakarta", "Café", "鎌倉駅", "123 Main Street", "Museum, Jakarta"])
        precondition(
            NativeTripListInput.names(from: "7-Eleven\n101. Dalmatians Cafe").first == "7-Eleven")
        print("PASS 2: numbered/bulleted input preserves addresses, Unicode, order and repeats")

        try draft.appendPlaces(input)
        precondition(Set(draft.stops.map(\.id)).count == 5)
        precondition(
            draft.stops.allSatisfy {
                $0.role == .visit && $0.exposure == .unknown && $0.point.coordinate == nil
                    && $0.dwell(defaultMinutes: draft.defaultDwell) == 30
            })
        let firstID = draft.stops[0].id
        try draft.appendPlaces("Last stop")
        precondition(draft.stops[0].id == firstID && draft.stops.count == 6)
        print("PASS 3: append retains existing stops; repeated visits have independent stable IDs")

        let snapshot = draft
        do {
            try draft.appendPlaces(Array(repeating: "Overflow", count: 15).joined(separator: "\n"))
            preconditionFailure("Expected overflow rejection")
        } catch { precondition(draft == snapshot) }
        do {
            try draft.appendPlaces(" \n")
            preconditionFailure("Expected empty rejection")
        } catch { precondition(draft == snapshot) }
        print("PASS 4: empty/over-capacity input rejected atomically, without truncation")

        precondition(
            NativeTripListInput.searchQuery(name: " Museum ", context: " Jakarta, Indonesia ")
                == "Museum, Jakarta, Indonesia")
        precondition(
            NativeTripListInput.searchQuery(name: "Museum JAKARTA", context: "Jakarta")
                == "Museum JAKARTA")
        precondition(NativeTripListInput.searchQuery(name: "  ", context: "Tokyo").isEmpty)
        print(
            "PASS 5: city context supplements real queries without creating searches from blank names")

        let before = draft.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: draft.departure)
        draft.changeTimeZone(to: "Europe/London")
        let after = draft.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: draft.departure)
        precondition(before == after && draft.timeZoneID == "Europe/London")
        let valid = draft
        draft.changeTimeZone(to: "not-a-timezone")
        precondition(draft == valid)
        print("PASS 6: arbitrary valid time zone preserves local date/time; invalid zone rejected")

        let example = NativeTripDraft.japanExample()
        precondition(example.timeZoneID == "Asia/Tokyo" && example.stops.count == 15)
        precondition(example.stops.filter { $0.role == .transfer }.count == 4)
        precondition(example.calendar.component(.hour, from: example.departure) == 7)
        print("PASS 7: original Japan example remains an explicit optional fixture")

        do {
            try draft.validate()
            preconditionFailure("Expected unresolved location rejection")
        } catch {}
        draft.origin.title = "My start"
        draft.origin.latitude = -6.17
        draft.origin.longitude = 106.82
        for i in draft.stops.indices {
            draft.stops[i].point.latitude = -6.18 - Double(i) * 0.001
            draft.stops[i].point.longitude = 106.83
            draft.stops[i].point.selectionSource = "Pin manual pengguna"
        }
        try draft.validate()
        precondition(draft.endPoint.id == draft.origin.id)
        draft.returnsToOrigin = false
        do {
            try draft.validate()
            preconditionFailure("Expected missing endpoint rejection")
        } catch {}
        draft.end.title = "My end"
        draft.end.latitude = -6.2
        draft.end.longitude = 106.85
        try draft.validate()
        print(
            "PASS 8: arbitrary manual pins accepted; explicit distinct endpoint must also be resolved")
        let ambiguousPoint = NativeTripPoint(id: "kota", title: "Kota Tua", query: "Kota Tua")
        let wrong = NativeTripMatch(
            id: "sumatra", name: "Kota Tua", address: "Tapanuli Selatan, North Sumatra, Indonesia",
            latitude: 1.0078258, longitude: 99.4048783)
        let correct = NativeTripMatch(
            id: "jakarta", name: "Kota Tua", address: "Kota Tua, Jakarta, Indonesia",
            latitude: -6.135, longitude: 106.813)
        precondition(
            NativeTripLocationSelection.automaticMatch([wrong], point: ambiguousPoint, context: "") == nil
        )
        precondition(
            NativeTripLocationSelection.automaticMatch([wrong], point: ambiguousPoint, context: "Jakarta")
                == nil)
        precondition(
            NativeTripLocationSelection.automaticMatch(
                [correct], point: ambiguousPoint, context: "Jakarta, Indonesia") == correct)
        var regional = ambiguousPoint
        regional.searchRegion = .init(label: "Jakarta", latitude: -6.2, longitude: 106.82)
        precondition(
            NativeTripLocationSelection.automaticMatch([wrong], point: regional, context: "") == nil)
        precondition(
            NativeTripLocationSelection.automaticMatch([correct], point: regional, context: "") == correct
        )
        draft.stops[0].point.latitude = wrong.latitude
        draft.stops[0].point.longitude = wrong.longitude
        precondition(draft.locationWarnings.count == 1)
        draft.stops[0].point.latitude = correct.latitude
        draft.stops[0].point.longitude = correct.longitude
        precondition(draft.locationWarnings.isEmpty)
        print(
            "PASS 9: matching names need geographic context; distant Sumatra pin flagged without banning long trips"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let oldData = try encoder.encode(draft)
        let oldDraft = try decoder.decode(NativeTripDraft.self, from: oldData)
        precondition(oldDraft.automobile == nil)
        precondition(!draft.modes.contains(.automobile))
        draft.automobile = true
        let restored = try decoder.decode(NativeTripDraft.self, from: encoder.encode(draft))
        precondition(restored.modes.contains(.automobile) && restored.modes.count == 3)
        print("PASS 10: old drafts remain decodable; automobile is enabled only explicitly")
        print("10 local macOS input-policy checks passed. No network, Simulator, or iOS tests.")
    }
}
