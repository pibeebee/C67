import Foundation

/// Explicit authored demo provider factory using the separately dated sourced catalog.
@MainActor public enum BlokMReplay {
    public static func pipeline(city: Bool = false, expanded: Bool = false) throws -> IntegrationPipeline {
        let catalog = try IntegrationCatalog.load(blokM: !city, includeBlokM: expanded)
        let pipeline = IntegrationPipeline(catalog: catalog, search: BlokMReplaySearch(catalog: catalog),
                                           weather: TripWeatherCoordinator(provider: ReplayWeather()),
                                           logDirectory: FileManager.default.temporaryDirectory
                                               .appendingPathComponent("C67BlokMReplayLogs-\(UUID())"),
                                           buswayWalking: BuswayReplayWalking())
        pipeline.replayETA = { from, to, mode, departure in
            try Task.checkCancellation()
            return .init(id: "\(from.id)>\(to.id)", mode: mode, seconds: 1200,
                         distance: 5000, expectedDeparture: departure,
                         expectedArrival: departure.addingTimeInterval(1200), status: "available",
                         note: "Authored Blok M replay 20-minute leg; not live traffic.")
        }
        return pipeline
    }

    public static let origins: [PlacePin] = [
        ("Bundaran HI", -6.195, 106.823), ("Blok M", -6.244, 106.800),
        ("Cikini", -6.190, 106.839), ("Tebet", -6.238, 106.853),
        ("Senayan", -6.220, 106.807), ("Ragunan", -6.311, 106.820),
        ("Kuningan", -6.229, 106.832)
    ].map { name, latitude, longitude in
        var pin = PlacePin(id: "demo-origin-" + name, name: name, address: "Jakarta · titik contoh Demo",
                           latitude: latitude, longitude: longitude)
        pin.source = "Authored synthetic origin; not live MapKit"
        return pin
    }

    public static func request() throws -> TripRequest {
        let catalog = try IntegrationCatalog.load(blokM: true)
        var request = BlokMExperiment.request(now: BlokMExperiment.snapshotClock(catalog))
        request.requiredCandidateIDs = ["bm01", "bm04", "bm08"]
        return request
    }
}

@MainActor private final class BlokMReplaySearch: TripPlaceSearching {
    let catalog: IntegrationCatalog
    init(catalog: IntegrationCatalog) { self.catalog = catalog }
    func cancel() {}
    func search(query: String) async throws -> [PlacePin] {
        try Task.checkCancellation()
        if query == "Bundaran HI Jakarta" {
            var pin = PlacePin(id: "replay-origin", name: "Bundaran HI", address: "Jakarta Pusat",
                               latitude: -6.195, longitude: 106.823)
            pin.source = "Authored Blok M replay origin; not live search"
            return [pin]
        }
        guard let candidate = catalog.quality.candidates.first(where: { $0.mapQuery == query }),
              var pin = (catalog.region ?? (try? IntegrationCatalog.load(blokM: true).region))?.anchors.first(where: { $0.candidateID == candidate.id })?.pin
        else {
            guard catalog.region == nil else { return [] }
            return try await ReplaySearch().search(query: query)
        }
        pin.source = "Authored replay of catalog anchor; not a new MapKit observation"
        return [pin]
    }
}
