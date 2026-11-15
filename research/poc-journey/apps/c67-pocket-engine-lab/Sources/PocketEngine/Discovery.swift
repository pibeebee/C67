import Foundation

public enum Interests {
    private struct Taxonomy: Decodable {
        var types: [String: [String: String]]
        var subtypes: [String: [String: String]]
    }
    private static let taxonomy: Taxonomy? = Bundle.module.url(forResource: "preference-labels", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(Taxonomy.self, from: $0) }

    public struct Group: Identifiable, Sendable {
        public var title: String
        public var keys: [String]
        public var id: String { title }
    }

    public static let groups: [Group] = [
        Group(title: "Minat umum", keys: ["art", "garden", "animal", "sushi"])
    ] + (taxonomy?.types ?? [:]).keys.sorted().map { group in
        Group(title: group.replacingOccurrences(of: "_", with: " ").capitalized,
              keys: (taxonomy?.types[group]?.keys.sorted() ?? []).map(canonical))
    } + [Group(title: "Subtipe", keys: (taxonomy?.subtypes.values.flatMap { $0.keys } ?? []).sorted())]

    public static let all = groups.flatMap(\.keys)

    public static func canonical(_ key: String) -> String { key == "bookstore" ? "book_store" : key }

    public static func title(_ key: String) -> String {
        if let theme = PreferenceTheme.from(interest: key) { return theme.title }
        return titles[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static let titles = [
        "cafe": "Kafe", "restaurant": "Restoran", "bakery": "Toko roti", "dessert_shop": "Toko pencuci mulut",
        "tea_house": "Kedai teh", "food_court": "Pujasera", "street_food_area": "Sentra jajanan",
        "park": "Taman publik", "botanical_garden": "Kebun botani", "urban_forest": "Hutan kota",
        "public_square": "Alun-alun", "waterfront_walk": "Jalur tepi air",
        "museum": "Museum", "art_gallery": "Galeri seni", "cultural_center": "Pusat kebudayaan",
        "heritage_site": "Situs bersejarah", "cinema": "Bioskop", "performance_venue": "Tempat pertunjukan",
        "live_music_venue": "Tempat musik langsung", "karaoke": "Karaoke",
        "library": "Perpustakaan", "book_store": "Toko buku", "coworking_space": "Ruang kerja bersama",
        "creative_studio": "Studio kreatif", "workshop_venue": "Tempat lokakarya",
        "shopping_mall": "Pusat belanja", "traditional_market": "Pasar tradisional", "thrift_shop": "Toko barang bekas",
        "record_store": "Toko rekaman", "craft_shop": "Toko kerajinan",
        "sports_center": "Pusat olahraga", "swimming_pool": "Kolam renang", "climbing_gym": "Tempat panjat",
        "bowling_alley": "Arena boling", "arcade": "Arena arkade", "playground": "Taman bermain",
        "cycling_track": "Lintasan sepeda", "specialty_coffee": "Kopi spesialti", "brunch_cafe": "Kafe brunch",
        "dessert_cafe": "Kafe pencuci mulut", "indonesian_cuisine": "Masakan Indonesia",
        "japanese_cuisine": "Masakan Jepang", "korean_cuisine": "Masakan Korea",
        "art_museum": "Museum seni", "history_museum": "Museum sejarah", "science_museum": "Museum sains",
        "used_books": "Buku bekas", "comics": "Komik", "childrens_books": "Buku anak",
        "indoor": "Area dalam ruang", "semi_outdoor": "Area semi-outdoor", "rooftop": "Area atap",
        "garden_seating": "Tempat duduk di taman", "nature": "Daya tarik alam", "heritage": "Warisan budaya",
        "architecture": "Arsitektur", "city_view": "Pemandangan kota", "public_art": "Seni publik",
        "local_cuisine": "Kuliner lokal", "walking_path": "Jalur pejalan kaki", "children_play_area": "Area bermain anak",
        "art": "Seni", "garden": "Taman dan kebun", "animal": "Hewan", "sushi": "Sushi"
    ]

    public static func query(_ key: String) -> String {
        ["restaurant": "restaurant", "japanese_cuisine": "Japanese restaurant", "sushi": "sushi", "animal": "zoo aquarium",
         "art": "art gallery museum", "art_gallery": "art gallery", "garden": "park garden", "book_store": "bookstore",
         "library": "library", "shopping_mall": "shopping mall"][key] ?? key.replacingOccurrences(of: "_", with: " ")
    }
    public static func matches(_ interest: String, categories: [String]) -> Bool {
        let interest = canonical(interest)
        let equivalents: [String: Set<String>] = [
            "art": ["art", "art_gallery", "art_museum"], "garden": ["garden", "park", "botanical_garden"],
            "animal": ["animal", "zoo", "aquarium"], "restaurant": ["restaurant", "japanese_cuisine", "sushi", "korean_cuisine", "indonesian_cuisine"],
            "japanese_cuisine": ["japanese_cuisine", "sushi"],
            "museum": ["museum", "art_museum", "history_museum", "science_museum"],
            "cafe": ["cafe", "specialty_coffee", "brunch_cafe", "dessert_cafe"],
            "book_store": ["book_store", "used_books", "comics", "childrens_books"]
        ]
        return !Set(categories.map(canonical)).isDisjoint(with: equivalents[interest] ?? [interest])
    }
}

public struct VisitArea: Codable, Sendable {
    public var name: String
    public var sourceURL: String
    public var attribution: String
    public var geometry: Geometry
    public struct Geometry: Codable, Sendable {
        public var type: String
        public var coordinates: [[[[Double]]]]
        enum CodingKeys: CodingKey { case type, coordinates }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            switch type {
            case "MultiPolygon": coordinates = try c.decode([[[[Double]]]].self, forKey: .coordinates)
            case "Polygon": coordinates = [try c.decode([[[Double]]].self, forKey: .coordinates)]
            default: throw EngineError.invalid("Batas area harus Polygon atau MultiPolygon.")
            }
            guard !coordinates.isEmpty, coordinates.allSatisfy({ polygon in
                !polygon.isEmpty && polygon.allSatisfy { ring in
                    ring.count >= 4 && ring.allSatisfy { $0.count == 2 && Coordinate(latitude: $0[1], longitude: $0[0]).valid }
                }
            }) else { throw EngineError.invalid("Koordinat batas area tidak valid.") }
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("MultiPolygon", forKey: .type)
            try c.encode(coordinates, forKey: .coordinates)
        }
    }
    public static var bundledNames: [String] {
        ["Jakarta Selatan", "Kemayoran"].filter { name in
            (try? bundled(named: name)) != nil
        }
    }
    public static func jakartaSelatan() throws -> Self { try bundled(named: "Jakarta Selatan") }
    public static func bundled(named name: String) throws -> Self {
        let resources = ["Jakarta Selatan": "jakarta-selatan", "Kemayoran": "kemayoran"]
        guard let resource = resources[name], let url = Bundle.module.url(forResource: resource, withExtension: "json") else {
            throw EngineError.invalid("Batas wilayah belum tersedia: " + name)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    public func contains(_ point: Coordinate) -> Bool {
        guard point.valid else { return false }
        func inside(_ ring: [[Double]]) -> Bool {
            var contained = false
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let cross = (point.longitude - a[0]) * (b[1] - a[1]) - (point.latitude - a[1]) * (b[0] - a[0])
                if abs(cross) < 1e-12 && (min(a[0], b[0]) ... max(a[0], b[0])).contains(point.longitude) &&
                    (min(a[1], b[1]) ... max(a[1], b[1])).contains(point.latitude) { return true }
                if (a[1] > point.latitude) != (b[1] > point.latitude) {
                    let longitude = (b[0] - a[0]) * (point.latitude - a[1]) / (b[1] - a[1]) + a[0]
                    if point.longitude < longitude { contained.toggle() }
                }
            }
            return contained
        }
        return geometry.coordinates.contains { polygon in
            inside(polygon[0]) && !polygon.dropFirst().contains(where: inside)
        }
    }
    public func permits(_ point: Coordinate, extensionMeters: Double = 0) -> Bool {
        if contains(point) { return true }
        guard extensionMeters > 0 else { return false }
        // Distance to every boundary segment, projected locally in meters.
        let scaleX = cos(point.latitude * .pi / 180) * 111_195.0
        let scaleY = 111_195.0
        for ring in geometry.coordinates.flatMap({ $0 }) {
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let ax = (a[0] - point.longitude) * scaleX, ay = (a[1] - point.latitude) * scaleY
                let dx = (b[0] - a[0]) * scaleX, dy = (b[1] - a[1]) * scaleY
                let length = dx * dx + dy * dy
                let fraction = length == 0 ? 0 : min(1, max(0, -(ax * dx + ay * dy) / length))
                if hypot(ax + fraction * dx, ay + fraction * dy) <= extensionMeters { return true }
            }
        }
        return false
    }
}

public enum CandidatePool {
    public static func normalizedName(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    public static func merge(independent: [Venue], session: [Venue]) -> [Venue] {
        var result: [Venue] = []
        var ids = Set<String>()
        var names: [String: [Int]] = [:]
        for candidate in independent + session where !ids.contains(candidate.id) {
            let keys = Set(([candidate.name] + candidate.aliases).map(normalizedName))
            let possible = Set(keys.flatMap { names[$0] ?? [] })
            let matches = possible.filter { result[$0].coordinate.distance(to: candidate.coordinate) <= 125 }
            ids.insert(candidate.id)
            if matches.count == 1, let index = matches.first {
                if candidate.id.hasPrefix("apple-session-") { continue }
                // Independent sources can add categories/provenance; conflicting facts remain visible to status().
                result[index].categories = Array(Set(result[index].categories + candidate.categories)).sorted()
                result[index].sourceURLs = Array(Set(result[index].sourceURLs + candidate.sourceURLs)).sorted()
                result[index].operatorURLs = Array(Set(result[index].operatorURLs + candidate.operatorURLs)).sorted()
                result[index].aliases = Array(Set(result[index].aliases + candidate.aliases + [candidate.name])
                    .subtracting([result[index].name])).sorted()
                if result[index].facts.count + candidate.facts.count <= Facet.allCases.count * 2 {
                    result[index].facts += candidate.facts
                } else {
                    // An overfull merge cannot establish a required condition.
                    result[index].facts = []
                }
                if result[index].hours == nil { result[index].hours = candidate.hours }
                if !result[index].license.contains(candidate.license) { result[index].license += " · " + candidate.license }
                let aliases = keys.union(([result[index].name] + result[index].aliases).map(normalizedName))
                for key in aliases where !(names[key] ?? []).contains(index) { names[key, default: []].append(index) }
                continue
            }
            // Ambiguous branch matches cannot count as another distinct recommendation.
            if matches.count > 1 { continue }
            let index = result.count
            result.append(candidate)
            for key in keys { names[key, default: []].append(index) }
        }
        return result
    }
}
