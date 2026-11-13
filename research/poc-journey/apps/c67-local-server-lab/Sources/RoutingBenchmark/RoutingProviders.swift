import Foundation
import PlaceContextEngine
import PlannerEngine

enum RoutingWire {
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 5 * 1024 * 1024, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RoutingFailure.invalidResponse }
        return value
    }
    static func point(_ value: Any?) -> RoutingPoint? {
        guard let value = value as? [String: Any], let lat = value["latitude"] as? Double, let lon = value["longitude"] as? Double else { return nil }
        let point = RoutingPoint(lat, lon); return point.valid ? point : nil
    }
    static func duration(_ value: Any?) -> Double? {
        guard let text = value as? String, text.hasSuffix("s"), let number = Double(text.dropLast()), number.isFinite, number >= 0 else { return nil }
        return number
    }
    static func check(_ status: Int) throws {
        switch status { case 200: return; case 401, 403: throw RoutingFailure.authentication; case 429: throw RoutingFailure.throttled; case 404, 422: throw RoutingFailure.unavailable; default: throw RoutingFailure.transport }
    }
    static func send(_ request: URLRequest, http: any PlacesHTTPTransport) async throws -> Data {
        try Task.checkCancellation()
        do {
            let response = try await http.send(request)
            try Task.checkCancellation(); try check(response.status)
            guard response.data.count <= 5 * 1024 * 1024 else { throw RoutingFailure.invalidResponse }
            return response.data
        } catch is CancellationError { throw CancellationError() }
        catch let error as RoutingFailure { throw error }
        catch let error as URLError where error.code == .timedOut { throw RoutingFailure.deadlineExceeded }
        catch { try Task.checkCancellation(); throw RoutingFailure.transport }
    }
    static func jsonRequest(url: URL, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        return request
    }
    static func localTime(_ date: Date) -> String {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(identifier: "Asia/Jakarta"); format.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return format.string(from: date)
    }
    static func polyline(_ encoded: String, precision: Double = 1e6) throws -> [RoutingPoint] {
        let bytes = Array(encoded.utf8)
        guard bytes.count <= 1000000 else { throw RoutingFailure.invalidResponse }
        var cursor = 0, lat = 0, lon = 0; var points: [RoutingPoint] = []
        func component() throws -> Int {
            var value = 0, shift = 0
            while cursor < bytes.count, shift <= 30 {
                let byte = Int(bytes[cursor]) - 63; cursor += 1
                guard (0 ... 63).contains(byte) else { throw RoutingFailure.invalidResponse }
                value |= (byte & 31) << shift
                if byte < 32 { return value & 1 == 1 ? ~(value >> 1) : value >> 1 }
                shift += 5
            }
            throw RoutingFailure.invalidResponse
        }
        while cursor < bytes.count {
            lat += try component(); lon += try component()
            let point = RoutingPoint(Double(lat) / precision, Double(lon) / precision)
            guard point.valid else { throw RoutingFailure.invalidResponse }
            points.append(point)
        }
        return points
    }
}

@MainActor public final class GoogleRoutingProvider: RoutingProvider {
    public let name = "google_routes"
    public let budget: RoutingBudget
    private let key: String
    private let http: any PlacesHTTPTransport
    public init(key: String, budget: RoutingBudget, http: any PlacesHTTPTransport = PlacesURLSession()) throws {
        guard !key.isEmpty, key.count <= 256, !key.contains(where: \.isWhitespace) else { throw RoutingFailure.missingConfiguration }
        self.key = key; self.budget = budget; self.http = http
    }
    private func waypoint(_ endpoint: RoutingEndpoint) throws -> [String: Any] {
        try endpoint.validate()
        if let id = endpoint.googlePlaceID { return ["placeId": id] }
        guard let p = endpoint.point else { throw RoutingFailure.invalidInput }
        return ["location": ["latLng": ["latitude": p.latitude, "longitude": p.longitude]]]
    }
    private func request(path: String, body: [String: Any], mask: String, elements: Int = 0) async throws -> Data {
        var request = try RoutingWire.jsonRequest(url: URL(string: "https://routes.googleapis.com/" + path)!, body: body)
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key"); request.setValue(mask, forHTTPHeaderField: "X-Goog-FieldMask")
        try Task.checkCancellation(); try budget.reserve(elements: elements)
        return try await RoutingWire.send(request, http: http)
    }
    public func route(_ query: RoutingQuery) async throws -> RoutingResult? {
        try query.validate()
        var body: [String: Any] = ["origin": try waypoint(query.from), "destination": try waypoint(query.to), "travelMode": query.mode == .walking ? "WALK" : "DRIVE", "computeAlternativeRoutes": false]
        if query.mode == .automobile { body["routingPreference"] = "TRAFFIC_AWARE"; body["departureTime"] = query.departure.ISO8601Format() }
        var mask = "routes.duration,routes.distanceMeters,routes.legs.startLocation,routes.legs.endLocation"
        if query.geometry { mask += ",routes.polyline.encodedPolyline" }
        let data = try await request(path: "directions/v2:computeRoutes", body: body, mask: mask)
        let object = try RoutingWire.object(data)
        guard let routes = object["routes"] as? [[String: Any]] else { return nil }
        guard let route = routes.first else { return nil }
        guard let seconds = RoutingWire.duration(route["duration"]), let meters = route["distanceMeters"] as? Double,
              let legs = route["legs"] as? [[String: Any]], legs.count == 1,
              let start = RoutingWire.point((legs[0]["startLocation"] as? [String: Any])?["latLng"]),
              let end = RoutingWire.point((legs[0]["endLocation"] as? [String: Any])?["latLng"]) else { throw RoutingFailure.invalidResponse }
        let line = (route["polyline"] as? [String: Any])?["encodedPolyline"] as? String
        let geometry = try line.map { try RoutingWire.polyline($0, precision: 1e5) } ?? []
        return try .init(query: query, seconds: seconds, meters: meters, snappedFrom: start, snappedTo: end, geometry: geometry, source: name, traffic: query.mode == .automobile ? "TRAFFIC_AWARE" : "not_applicable")
    }
    /// Matrix values are search priors, not final itinerary evidence. Missing cells remain nil.
    public func matrix(sources: [RoutingEndpoint], targets: [RoutingEndpoint], mode: RouteMode, departure: Date) async throws -> [[Double?]] {
        guard !sources.isEmpty, !targets.isEmpty, sources.count <= 25, targets.count <= 25 else { throw RoutingFailure.invalidInput }
        var body: [String: Any] = ["origins": try sources.map { ["waypoint": try waypoint($0)] }, "destinations": try targets.map { ["waypoint": try waypoint($0)] }, "travelMode": mode == .walking ? "WALK" : "DRIVE"]
        if mode == .automobile { body["routingPreference"] = "TRAFFIC_AWARE"; body["departureTime"] = departure.ISO8601Format() }
        let data = try await request(path: "distanceMatrix/v2:computeRouteMatrix", body: body, mask: "originIndex,destinationIndex,status,condition,duration", elements: sources.count * targets.count)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw RoutingFailure.invalidResponse }
        var output = Array(repeating: Array<Double?>(repeating: nil, count: targets.count), count: sources.count), seen = Set<String>()
        for row in rows {
            guard let a = row["originIndex"] as? Int, let b = row["destinationIndex"] as? Int, sources.indices.contains(a), targets.indices.contains(b), seen.insert("\(a):\(b)").inserted else { throw RoutingFailure.invalidResponse }
            let code = (row["status"] as? [String: Any])?["code"] as? Int ?? 0
            if [7, 16].contains(code) { throw RoutingFailure.authentication }
            if code == 8 { throw RoutingFailure.throttled }
            if code == 0, row["condition"] as? String == "ROUTE_EXISTS" { output[a][b] = RoutingWire.duration(row["duration"]) }
        }
        return output
    }
    /// Acquisition shares the campaign budget and never persists the raw response.
    public func resolve(_ venue: RoutingVenue) async throws -> String? {
        guard !venue.name.isEmpty, venue.name.count <= 240 else { throw RoutingFailure.invalidInput }
        var request = try RoutingWire.jsonRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!, body: ["textQuery": venue.name + " " + venue.area + " Jakarta", "pageSize": 5, "regionCode": "ID"])
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key"); request.setValue("places.id,places.displayName,places.location", forHTTPHeaderField: "X-Goog-FieldMask")
        try Task.checkCancellation(); try budget.reserve()
        let object = try RoutingWire.object(try await RoutingWire.send(request, http: http))
        let candidates = (object["places"] as? [[String: Any]] ?? []).filter { value in
            guard let text = (value["displayName"] as? [String: Any])?["text"] as? String, let point = RoutingWire.point(value["location"]) else { return false }
            return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "id_ID")) == venue.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "id_ID")) && point.distance(to: venue.displayPoint) <= 150
        }
        guard candidates.count == 1 else { return nil }
        let id = candidates[0]["id"] as? String
        guard id.map(GooglePlacesClient.validID) == true else { throw RoutingFailure.invalidResponse }; return id
    }
    public func snapshot(placeID: String, now: Date) async throws -> (snapshot: PlaceSnapshot, entrances: Int, navigationPoints: Int) {
        guard GooglePlacesClient.validID(placeID) else { throw RoutingFailure.invalidInput }
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places/" + placeID + "?languageCode=id&regionCode=ID")!)
        let mask = GooglePlacesClient.hoursMask + ",entrances,navigationPoints"
        request.timeoutInterval = 25; request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key"); request.setValue(mask, forHTTPHeaderField: "X-Goog-FieldMask")
        try Task.checkCancellation(); try budget.reserve()
        let data = try await RoutingWire.send(request, http: http)
        let place = try JSONDecoder().decode(GooglePlace.self, from: data)
        guard place.id == placeID else { throw RoutingFailure.invalidResponse }
        let object = try RoutingWire.object(data)
        return (.init(place: place, fetchedAt: now, fieldMask: mask), (object["entrances"] as? [Any])?.count ?? 0, (object["navigationPoints"] as? [Any])?.count ?? 0)
    }
}

@MainActor public final class ValhallaRoutingProvider: RoutingProvider {
    public let name = "valhalla_osm"
    private let baseURL: URL
    private let http: any PlacesHTTPTransport
    public private(set) var requests = 0
    public init(baseURL: URL, http: any PlacesHTTPTransport = PlacesURLSession()) throws {
        guard ["127.0.0.1", "localhost", "::1"].contains(baseURL.host ?? ""), baseURL.scheme == "http", baseURL.user == nil, baseURL.password == nil, baseURL.query == nil else { throw RoutingFailure.invalidInput }
        self.baseURL = baseURL; self.http = http
    }
    public func route(_ query: RoutingQuery) async throws -> RoutingResult? {
        try query.validate()
        guard let from = query.from.point, let to = query.to.point else { throw RoutingFailure.invalidInput }
        let body: [String: Any] = ["locations": [["lat": from.latitude, "lon": from.longitude, "radius": 50], ["lat": to.latitude, "lon": to.longitude, "radius": 50]], "costing": query.mode == .walking ? "pedestrian" : "auto", "units": "kilometers", "date_time": ["type": 1, "value": RoutingWire.localTime(query.departure)]]
        try Task.checkCancellation(); requests += 1
        let request = try RoutingWire.jsonRequest(url: baseURL.appendingPathComponent("route"), body: body)
        let object = try RoutingWire.object(try await RoutingWire.send(request, http: http))
        guard let trip = object["trip"] as? [String: Any], trip["status"] as? Int == 0, trip["units"] as? String == "kilometers",
              let summary = trip["summary"] as? [String: Any], let seconds = summary["time"] as? Double, let km = summary["length"] as? Double,
              let legs = trip["legs"] as? [[String: Any]], legs.count == 1, let encoded = legs[0]["shape"] as? String else { throw RoutingFailure.invalidResponse }
        let points = try RoutingWire.polyline(encoded)
        guard let start = points.first, let end = points.last, start.distance(to: from) <= 100, end.distance(to: to) <= 100 else { throw RoutingFailure.invalidResponse }
        return try .init(query: query, seconds: seconds, meters: km * 1000, snappedFrom: start, snappedTo: end, geometry: query.geometry ? points : [], source: name, traffic: "OSM static speeds; no live traffic")
    }
}

@MainActor public final class AppleRoutingProvider: RoutingProvider {
    public let name = "apple_maps_rest"
    private let apple: LabAppleREST
    private let eta: LabRESTETA
    public init(apple: LabAppleREST) { self.apple = apple; eta = LabRESTETA(apple: apple) }
    public func route(_ query: RoutingQuery) async throws -> RoutingResult? {
        try query.validate()
        guard let a = query.from.point, let b = query.to.point else { throw RoutingFailure.invalidInput }
        let q = LabETAQuery(fromID: query.from.id, toID: query.to.id, fromLatitude: a.latitude, fromLongitude: a.longitude, toLatitude: b.latitude, toLongitude: b.longitude, mode: query.mode.rawValue, departure: query.departure)
        if !query.geometry {
            let values = try await eta.values([q]); try Task.checkCancellation()
            guard let value = values.first, value.query == q, value.status == "available", let seconds = value.seconds, let meters = value.distance else { return nil }
            return try .init(query: query, seconds: seconds, meters: meters, source: name, traffic: "Apple exact requested departure; endpoint geometry not requested")
        }
        let data = try await apple.maps(path: "directions", params: [.init(name: "origin", value: "\(a.latitude),\(a.longitude)"), .init(name: "destination", value: "\(b.latitude),\(b.longitude)"), .init(name: "transportType", value: query.mode == .walking ? "Walking" : "Automobile"), .init(name: "departureDate", value: query.departure.ISO8601Format())])
        try Task.checkCancellation()
        let object = try RoutingWire.object(data)
        guard let route = (object["routes"] as? [[String: Any]])?.first else { return nil }
        guard let seconds = route["durationSeconds"] as? Double, let meters = route["distanceMeters"] as? Double,
              let steps = object["steps"] as? [[String: Any]], let paths = object["stepPaths"] as? [[Any]], let indices = route["stepIndexes"] as? [Int] else { throw RoutingFailure.invalidResponse }
        var points: [RoutingPoint] = []
        for index in indices {
            guard steps.indices.contains(index), let path = steps[index]["stepPathIndex"] as? Int, paths.indices.contains(path) else { throw RoutingFailure.invalidResponse }
            for value in paths[path] { guard let p = RoutingWire.point(value) else { throw RoutingFailure.invalidResponse }; points.append(p) }
        }
        return try .init(query: query, seconds: seconds, meters: meters, snappedFrom: points.first, snappedTo: points.last, geometry: points, source: name, traffic: "Apple directions exact departure")
    }
    public static func configured(environment: [String: String]) throws -> AppleRoutingProvider {
        let required = ["APPLE_TEAM_ID", "MAPS_KEY_ID", "MAPS_KEY_PATH"]
        guard required.allSatisfy({ environment[$0]?.isEmpty == false }) else { throw RoutingFailure.missingConfiguration }
        // LabAppleREST's shared configuration requires weather fields. This benchmark
        // never calls weather; these map-key placeholders are not WeatherKit credentials.
        var env = environment
        env["WEATHER_KEY_ID"] = env["MAPS_KEY_ID"]; env["WEATHER_KEY_PATH"] = env["MAPS_KEY_PATH"]; env["WEATHER_SERVICE_ID"] = "unused-routing-benchmark"
        return try .init(apple: LabAppleREST(config: .init(environment: env)))
    }
}
