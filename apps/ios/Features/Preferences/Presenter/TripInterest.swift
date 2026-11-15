import Foundation

/// Q1 "What sounds good today?" — the kinds of places the traveller wants. Multi-select.
enum TripInterest: String, CaseIterable, Hashable, Identifiable, Sendable {
    case foodie
    case nature
    case photoSpot
    case culture
    case lifestyle
    case art
    case entertainment

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .foodie: "Foodie"
        case .nature: "Nature"
        case .photoSpot: "Photo Spot"
        case .culture: "Culture"
        case .lifestyle: "Lifestyle"
        case .art: "Art"
        case .entertainment: "Entertainment"
        }
    }

    /// SF Symbol matching the Sketch glyph.
    var systemImage: String {
        switch self {
        case .foodie: "fork.knife"
        case .nature: "tree.circle.fill"
        case .photoSpot: "camera.aperture"
        case .culture: "building.columns.fill"
        case .lifestyle: "bag.fill"
        case .art: "paintpalette.fill"
        case .entertainment: "theatermasks.fill"
        }
    }
}

/// The expanded Q1 vocabulary. IDs that also exist in Pocket's taxonomy are shared with the engine.
enum TripPreferenceCatalog {
    struct Option: Identifiable, Sendable {
        let id: String
        let title: LocalizedStringResource

        init(_ id: String, _ title: LocalizedStringResource) {
            self.id = id
            self.title = title
        }
    }

    struct Group: Identifiable, Sendable {
        let id: String
        let title: LocalizedStringResource
        let systemImage: String
        let options: [Option]
    }

    static let groups: [Group] = [
        .init(id: "food-and-drink", title: "Food & drink places", systemImage: "fork.knife", options: [
            .init("restaurant", "Restaurant"),
            .init("ramen", "Ramen shop"),
            .init("yakitori", "Yakitori bar"),
            .init("sushi_omakase", "Sushi omakase"),
            .init("korean_bbq", "Korean barbecue"),
            .init("dim_sum", "Dim sum shop"),
            .init("cafe", "Café"),
            .init("coffee_roastery", "Coffee roastery"),
            .init("espresso_bar", "Espresso bar"),
            .init("tea_house", "Tea house"),
            .init("dessert_shop", "Dessert shop"),
            .init("bakery", "Bakery"),
            .init("cake_shop", "Cake shop"),
            .init("traditional_market", "Traditional market"),
            .init("night_food", "Night food market"),
            .init("farmers_market", "Farmers market"),
            .init("seafood_market", "Seafood market"),
            .init("grocery_store", "Grocery store"),
            .init("food_court", "Food court"),
            .init("street_food_area", "Street food area"),
            .init("brewery", "Brewery"),
            .init("winery", "Winery"),
            .init("distillery", "Distillery"),
        ]),
        .init(id: "cuisine-and-menu", title: "Cuisine & menu", systemImage: "menucard", options: [
            .init("japanese_cuisine", "Japanese cuisine"),
            .init("korean_cuisine", "Korean cuisine"),
            .init("indonesian_cuisine", "Indonesian cuisine"),
            .init("chinese_cuisine", "Chinese cuisine"),
            .init("thai_cuisine", "Thai cuisine"),
            .init("vietnamese_cuisine", "Vietnamese cuisine"),
            .init("indian_cuisine", "Indian cuisine"),
            .init("middle_eastern_cuisine", "Middle Eastern cuisine"),
            .init("italian_cuisine", "Italian cuisine"),
            .init("padang_cuisine", "Padang cuisine"),
            .init("betawi_cuisine", "Betawi cuisine"),
            .init("manado_cuisine", "Manado cuisine"),
            .init("sundanese_cuisine", "Sundanese cuisine"),
            .init("peranakan_cuisine", "Peranakan cuisine"),
            .init("seafood", "Seafood"),
            .init("vegetarian_options", "Vegetarian"),
            .init("vegan_options", "Vegan"),
            .init("breakfast", "Breakfast"),
            .init("brunch_cafe", "Brunch"),
            .init("specialty_coffee", "Specialty coffee"),
            .init("manual_brew", "Manual brew coffee"),
            .init("kopi_susu", "Kopi susu"),
            .init("matcha", "Matcha"),
            .init("chocolate", "Chocolate"),
            .init("sourdough", "Sourdough"),
            .init("french_pastry", "French pastry"),
            .init("doughnuts", "Doughnuts"),
            .init("traditional_cakes", "Traditional cakes"),
        ]),
        .init(id: "nature-and-public-spaces", title: "Nature & public spaces", systemImage: "tree", options: [
            .init("city_park", "City park"),
            .init("neighborhood_park", "Neighborhood park"),
            .init("pocket_park", "Pocket park"),
            .init("rptra", "RPTRA"),
            .init("botanical_garden", "Botanical garden"),
            .init("urban_forest", "Urban forest"),
            .init("flower_garden", "Flower garden"),
            .init("mangrove_park", "Mangrove park"),
            .init("sculpture_park", "Sculpture park"),
            .init("national_park", "National park"),
            .init("beach", "Beach"),
            .init("campground", "Campground"),
            .init("nature_trail", "Nature trail"),
            .init("fishing_pond", "Fishing pond"),
            .init("marina", "Marina"),
            .init("waterfront_walk", "Waterfront walk"),
            .init("observation_deck", "Observation deck"),
        ]),
        .init(id: "culture-arts-and-learning", title: "Culture, art & learning", systemImage: "building.columns", options: [
            .init("museum", "Museum"),
            .init("art_gallery", "Art gallery"),
            .init("heritage_site", "Historic site"),
            .init("old_town", "Old town district"),
            .init("monument", "Monument"),
            .init("memorial", "Memorial"),
            .init("palace", "Palace"),
            .init("fort", "Fort"),
            .init("planetarium", "Planetarium"),
            .init("observatory", "Observatory"),
            .init("library", "Library"),
            .init("reading_room", "Reading room"),
            .init("campus", "Campus"),
            .init("performance_venue", "Theater"),
            .init("live_music_venue", "Music venue"),
            .init("cinema", "Cinema"),
            .init("visual_art", "Visual art"),
            .init("contemporary_museum", "Contemporary art"),
            .init("history", "History"),
            .init("maritime_culture", "Maritime culture"),
            .init("transportation_focus", "Transportation"),
            .init("science", "Science"),
            .init("textiles", "Textiles"),
            .init("wayang", "Wayang"),
            .init("ceramics", "Ceramics"),
            .init("photography_focus", "Photography exhibits"),
            .init("architecture", "Architecture"),
            .init("astronomy", "Astronomy"),
            .init("rare_collections", "Rare collections"),
        ]),
        .init(id: "shopping-and-personal-care", title: "Shopping & personal care", systemImage: "bag", options: [
            .init("independent_bookstore", "Independent bookstore"),
            .init("used_books", "Used bookstore"),
            .init("comics", "Comic book store"),
            .init("childrens_books", "Children’s bookstore"),
            .init("record_store", "Record store"),
            .init("thrift_shop", "Thrift shop"),
            .init("vintage_clothing_store", "Vintage clothing store"),
            .init("antique_shop", "Antique shop"),
            .init("collectibles_shop", "Collectibles shop"),
            .init("craft_shop", "Local craft shop"),
            .init("art_supply_store", "Art supply store"),
            .init("analog_camera_store", "Analog camera store"),
            .init("local_designer_store", "Local designer store"),
            .init("zero_waste_store", "Zero-waste store"),
            .init("shopping_mall", "Shopping mall"),
            .init("hair_salon", "Hair salon"),
            .init("nail_art_studio", "Nail art studio"),
            .init("barbershop", "Barbershop"),
            .init("spa", "Spa"),
            .init("exhibition_center", "Exhibition center"),
        ]),
        .init(id: "entertainment-and-sports", title: "Entertainment & sports", systemImage: "figure.run", options: [
            .init("amusement_park", "Amusement park"),
            .init("water_park", "Water park"),
            .init("aquarium", "Aquarium"),
            .init("zoo", "Zoo"),
            .init("bird_park", "Bird park"),
            .init("night_market", "Night market"),
            .init("bar", "Bar"),
            .init("karaoke", "Karaoke"),
            .init("arcade", "Arcade"),
            .init("bowling_alley", "Bowling"),
            .init("go_kart", "Go-karting"),
            .init("driving_range", "Driving range"),
            .init("golf_simulator", "Golf simulator"),
            .init("mini_golf", "Mini golf"),
            .init("climbing_gym", "Rock climbing"),
            .init("bouldering", "Bouldering"),
            .init("skate_park", "Skate park"),
            .init("bmx_park", "BMX park"),
            .init("ice_rink", "Ice skating rink"),
            .init("roller_rink", "Roller skating rink"),
            .init("swimming_pool", "Swimming pool"),
            .init("pilates_studio", "Pilates studio"),
            .init("yoga_studio", "Yoga studio"),
            .init("boxing_gym", "Boxing gym"),
            .init("stadium", "Stadium"),
            .init("baseball", "Baseball"),
            .init("basketball", "Basketball"),
            .init("futsal", "Futsal"),
            .init("mini_soccer", "Mini soccer"),
            .init("tennis", "Tennis"),
            .init("volleyball", "Volleyball"),
            .init("beach_volleyball", "Beach volleyball"),
        ]),
        .init(id: "activities", title: "Things to do", systemImage: "sparkles", options: [
            .init("picnic", "Picnic"),
            .init("jogging", "Jogging"),
            .init("walking", "Walking"),
            .init("photography_activity", "Taking photos"),
            .init("sunset_viewing", "Watching the sunset"),
            .init("camping", "Camping"),
            .init("glamping", "Glamping"),
            .init("kayaking", "Kayaking"),
            .init("fishing", "Fishing"),
            .init("surfing", "Surfing"),
            .init("boat_tour", "Boat tour"),
            .init("guided_tour", "Guided tour"),
            .init("interactive_exhibition", "Interactive exhibition"),
            .init("community_event", "Community event"),
            .init("live_music_activity", "Listening to live music"),
            .init("open_mic", "Open mic"),
            .init("film_festival", "Film festival"),
            .init("reading", "Reading"),
            .init("working", "Working"),
            .init("board_games", "Board games"),
            .init("drink_tasting", "Drink tasting"),
        ]),
        .init(id: "setting-facilities-and-access", title: "Setting, facilities & access", systemImage: "slider.horizontal.3", options: [
            .init("indoor", "Indoor"),
            .init("outdoor", "Outdoor"),
            .init("semi_outdoor", "Semi-outdoor"),
            .init("rooftop", "Rooftop"),
            .init("garden_seating", "Garden seating"),
            .init("lakeside", "Lakeside"),
            .init("riverside", "Riverside"),
            .init("seafront", "Seafront"),
            .init("city_view", "City view"),
            .init("quiet", "Quiet"),
            .init("family_friendly", "Family-friendly"),
            .init("pet_friendly", "Pet-friendly"),
            .init("dog_friendly", "Dog-friendly"),
            .init("beginner_friendly", "Beginner-friendly"),
            .init("private_room", "Private room"),
            .init("power_outlets", "Power outlets"),
            .init("children_play_area", "Children’s play area"),
            .init("wheelchair_path", "Wheelchair-accessible path"),
            .init("jogging_track", "Jogging track"),
            .init("equipment_rental", "Equipment rental"),
            .init("day_pass", "Day pass"),
            .init("public_access", "Public access"),
            .init("late_hours", "Open late"),
        ]),
    ]

    static let ids = Set(groups.flatMap(\.options).map(\.id))
}
