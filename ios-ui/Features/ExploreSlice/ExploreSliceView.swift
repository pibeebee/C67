import SwiftUI

enum MainTab: Hashable { case discover, journey, bookmark, search }

enum SampleCategory: String, CaseIterable, Identifiable {
    case heritage = "Heritage", food = "Food", coffee = "Coffee", nature = "Nature", night = "Night"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .heritage: "building.columns"
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer"
        case .nature: "leaf"
        case .night: "moon.stars"
        }
    }
}

private struct SampleJourney: Identifiable {
    let id: String
    let title: String
    let category: SampleCategory
    let summary: String
    static let examples: [Self] = [
        .init(id: "heritage", title: "Kota Tua Trail", category: .heritage, summary: "6 stops · 2.8 km · ~3 h"),
        .init(id: "nature", title: "Golden Hour Jakarta", category: .nature, summary: "4 stops · 3.1 km · ~2 h"),
        .init(id: "monas", title: "Monas & Merdeka", category: .heritage, summary: "4 stops · 2.2 km · ~2 h"),
        .init(id: "coffee", title: "Menteng Coffee Trail", category: .coffee, summary: "5 stops · 1.9 km · ~2.5 h"),
        .init(id: "food", title: "Jakarta Food Walk", category: .food, summary: "3 stops · 1.5 km · ~2 h"),
        .init(id: "night", title: "Jakarta at Night", category: .night, summary: "3 stops · 2 km · ~2 h"),
    ]
}

struct DiscoverSliceView: View {
    @Binding var selectedCategory: SampleCategory?
    let openSearch: () -> Void

    private var journeys: [SampleJourney] {
        SampleJourney.examples.filter { selectedCategory == nil || $0.category == selectedCategory }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Good afternoon, Johan").foregroundStyle(.secondary)
                    Spacer()
                    Button("Notifications", systemImage: "bell") {}.disabled(true)
                }
                Label("Menteng, Jakarta Pusat", systemImage: "location")
                    .font(.subheadline)
                Button(action: openSearch) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Search places or journeys")
                        Spacer()
                        Image(systemName: "mic")
                    }
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(SampleCategory.allCases) { category in
                            Button {
                                selectedCategory = selectedCategory == category ? nil : category
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: category.symbol).font(.title2)
                                    Text(category.rawValue).font(.caption)
                                }
                                .frame(minWidth: 54, minHeight: 56)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selectedCategory == category ? Color.accentColor : Color.primary)
                            .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                HStack {
                    Text("Journeys for you").font(.headline)
                    Spacer()
                    Button("See all", action: openSearch)
                }
                Text("Example journeys").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(journeys) { journey in
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.largeTitle).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).frame(height: 150)
                                    .background(.quaternary)
                                Text(journey.title).font(.headline)
                                Text(journey.summary).font(.subheadline).foregroundStyle(.secondary)
                                Text(journey.category.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 220, alignment: .leading)
                        }
                    }
                }.scrollIndicators(.hidden)
            }.padding()
        }
        .navigationTitle("Discover")
    }
}

struct SearchSliceView: View {
    @Binding var query: String
    @Binding var selectedCategory: SampleCategory?

    private var results: [SampleJourney] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SampleJourney.examples.filter { journey in
            (selectedCategory == nil || journey.category == selectedCategory) &&
                (text.isEmpty || journey.title.localizedCaseInsensitiveContains(text) || journey.category.rawValue.localizedCaseInsensitiveContains(text))
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search places or journeys", text: $query)
                        .autocorrectionDisabled()
                    Image(systemName: "mic").foregroundStyle(.secondary).accessibilityLabel("Voice search unavailable")
                }
                if let selectedCategory {
                    HStack {
                        Text("Category: \(selectedCategory.rawValue)")
                        Spacer()
                        Button("Clear") { self.selectedCategory = nil }
                    }.font(.subheadline)
                }
            }
            Section("Example journeys") {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query.isEmpty ? selectedCategory?.rawValue ?? "" : query)
                } else {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, journey in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 20)
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                                .frame(width: 52, height: 52)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(journey.title).font(.headline)
                                Text(journey.category.rawValue).font(.subheadline).foregroundStyle(.secondary)
                                Text(journey.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button("Start", systemImage: "play.fill") {}.disabled(true).labelStyle(.iconOnly)
                            Button("More", systemImage: "ellipsis") {}.disabled(true).labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
    }
}
