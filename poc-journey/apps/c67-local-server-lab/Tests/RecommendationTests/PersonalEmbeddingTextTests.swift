import XCTest
import RecommendationContracts
import PlaceContextEngine

final class PersonalEmbeddingTextTests: XCTestCase {
    private func place(_ type: String) -> PersonalCandidate {
        .init(id: "test-library", name: "Perpustakaan Nyaman", address: "Jalan Membaca",
              categories: [.reading], facetKeys: ["reading:" + type], description: "Tempat duduk tenang gratis",
              hoursState: "unknown", hours: [], evidence: [], unknowns: [], googleMapsURL: nil, exposure: .unknown)
    }
    func testQueryIsStableAcrossInterestOrderAndContainsNoUnaskedConstraints() {
        var p = PersonalProfile(); p.interests = [.reading, .coffee]
        let first = PersonalEmbeddingText.query(profile: p)
        p.interests.reverse()
        XCTAssertEqual(first, PersonalEmbeddingText.query(profile: p))
        XCTAssertTrue(first.contains("books and reading")); XCTAssertTrue(first.contains("coffee and cafes"))
        for invented in ["quiet", "vegetarian", "60", "30", "query:"] { XCTAssertFalse(first.contains(invented)) }
    }
    func testPassagesKeepLibraryAndBookStoreDistinctWithoutEmbeddingDisplayProse() {
        let library = PersonalEmbeddingText.passage(candidate: place("library"))
        let store = PersonalEmbeddingText.passage(candidate: place("book_store"))
        XCTAssertNotEqual(library, store)
        XCTAssertTrue(library.contains("library")); XCTAssertTrue(store.contains("book store"))
        for value in [library, store] {
            for untrusted in ["Perpustakaan", "Jalan", "tenang", "gratis", "passage:"] { XCTAssertFalse(value.contains(untrusted)) }
            XCTAssertTrue(value.contains("Other venue characteristics are unknown"))
        }
    }
    func testUnknownFacetCannotLeakUntranslatedOrInstructionText() {
        var c = place("ruang_tenang"); c.facetKeys.append("food:restaurant")
        let value = PersonalEmbeddingText.passage(candidate: c)
        XCTAssertTrue(value.contains("Provider categories: not provided"))
        XCTAssertFalse(value.contains("ruang")); XCTAssertFalse(value.contains("restaurant"))
        XCTAssertFalse(PersonalEmbeddingText.query(profile: PersonalProfile()).contains("reading"))
    }
}
