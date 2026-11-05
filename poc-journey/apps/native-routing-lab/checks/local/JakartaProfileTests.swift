import Foundation
import XCTest

@testable import C67LocalHarness

@MainActor final class JakartaProfileTests: XCTestCase {
    func repository() -> NativeTripLocalStore {
        .init(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
    func model(_ store: NativeTripLocalStore) -> NativeTripModel {
        .init(logs: .init(directory: store.directory.appendingPathComponent("logs")), localStore: store)
    }
    func testNewProfileUsesJakartaCarAndWIB() {
        let draft = NativeTripDraft.jakarta()
        XCTAssertEqual(draft.timeZoneID, "Asia/Jakarta")
        XCTAssertEqual(draft.modes, [.automobile])
        XCTAssertEqual(draft.carUse, NativeTripCarUse.onDemand.rawValue)
        XCTAssertEqual(draft.routingRequestLimit, 512)
        XCTAssertEqual(draft.selectedRoutingAlgorithm, .hybrid)
        XCTAssertTrue(draft.isJakartaProfile)
        XCTAssertTrue(model(repository()).draft.isJakartaProfile)
    }
    func testAllFiveUserLogPlacesAreInTheOperationalBoundary() throws {
        let draft = NativeTripDraft.jakartaFivePlaces()
        XCTAssertEqual(draft.stops.count, 5)
        XCTAssertTrue(draft.returnsToOrigin)
        XCTAssertNoThrow(try draft.validate())
        XCTAssertEqual(draft.clockMinutes(draft.departure), 480)
        XCTAssertEqual(draft.clockMinutes(draft.finishBy!), 1080)
        for point in draft.allPoints {
            XCTAssertTrue(
                NativeTripJakarta.contains(latitude: point.latitude!, longitude: point.longitude!),
                point.title)
        }
    }
    func testNearbyCitiesAndForeignPinsAreRejectedEvenWithJakartaInAddress() throws {
        for (lat, lon) in [(-6.238, 107.0), (-6.176, 106.638), (-6.402, 106.794), (35.70, 139.98)] {
            var draft = NativeTripDraft.jakartaFivePlaces()
            draft.stops[0].point.latitude = lat
            draft.stops[0].point.longitude = lon
            draft.stops[0].point.address = "Jakarta"
            XCTAssertThrowsError(try draft.validate())
        }
        XCTAssertFalse(NativeTripJakarta.contains(latitude: .nan, longitude: 106.8))
        XCTAssertFalse(NativeTripJakarta.contains(latitude: 0, longitude: .infinity))
    }
    func testEndpointOutsideScopeCannotPassValidation() {
        var draft = NativeTripDraft.jakartaFivePlaces()
        draft.returnsToOrigin = false
        draft.end = .init(
            id: "end", title: "Depok", query: "Depok", latitude: -6.402, longitude: 106.794)
        XCTAssertThrowsError(try draft.validate())
    }
    func testProfileRejectsTransitPrivateCarAndUnknownScope() {
        var draft = NativeTripDraft.jakartaFivePlaces()
        draft.transit = true
        XCTAssertThrowsError(try draft.validate())
        draft.transit = false
        draft.carUse = "privateCar"
        XCTAssertThrowsError(try draft.validate())
        draft.carUse = "onDemand"
        draft.planningArea = "unknown"
        XCTAssertThrowsError(try draft.validate())
    }
    func testLegacyDraftIsNotSilentlyConvertedOnRestore() throws {
        let store = repository()
        var old = NativeTripDraft.jakartaFivePlaces()
        old.planningArea = nil
        old.automobile = nil
        old.walking = true
        old.transit = true
        _ = try store.commit(.init(draft: old), expected: nil)
        let value = model(store)
        XCTAssertFalse(value.draft.isJakartaProfile)
        XCTAssertNil(value.draft.automobile)
        value.calculate()
        XCTAssertNotNil(value.error)
        XCTAssertFalse(value.isBusy)
        XCTAssertEqual(try store.load().session?.draft, old)
    }
    func testExplicitConversionPreservesCoordinatesAndDoesNotSaveUntilChosen() throws {
        let store = repository()
        var old = NativeTripDraft.jakartaFivePlaces()
        old.planningArea = nil
        old.automobile = nil
        old.walking = true
        old.transit = true
        _ = try store.commit(.init(draft: old), expected: nil)
        let value = model(store)
        value.adoptJakartaProfile()
        XCTAssertTrue(value.draft.isJakartaProfile)
        XCTAssertEqual(value.draft.stops.map { $0.point.latitude }, old.stops.map { $0.point.latitude })
        XCTAssertEqual(value.draft.stops.map(\.id), old.stops.map(\.id))
        XCTAssertNil(try store.load().session?.draft.planningArea)
        value.saveLocal()
        XCTAssertEqual(try store.load().session?.draft.planningArea, "jakarta")
    }
    func testOutOfScopeSelectionDoesNotReplaceCurrentPoint() {
        let value = model(repository())
        value.useJakartaExample()
        let before = value.draft.origin
        var wrong = before
        wrong.latitude = 35.70
        wrong.longitude = 139.98
        value.select(wrong)
        XCTAssertEqual(value.draft.origin, before)
        XCTAssertNotNil(value.error)
    }
    func testPastedNamesReceiveJakartaSearchHint() throws {
        var draft = NativeTripDraft.jakarta()
        try draft.appendPlaces("Kopi A\nKopi B")
        XCTAssertEqual(draft.stops.count, 2)
        XCTAssertTrue(draft.stops.allSatisfy { $0.point.searchRegion == NativeTripJakarta.region })
        XCTAssertTrue(draft.searchQuery(for: draft.stops[0].point).contains("Jakarta"))
    }
    func testOpenMeteoProfileNeverInvokesWeatherKit() async throws {
        var primaryCalls = 0
        var backupCalls = 0
        let result = try await NativeTripWeatherFallback.resolve(
            pointID: "C", primaryEnabled: false,
            primary: {
                primaryCalls += 1
                throw NativeTripWeatherFailure.invalidResponse
            },
            backup: {
                backupCalls += 1
                return .init(
                    pointID: "C", hours: [.init(date: Date(), rainChance: 0.4, temperatureC: 30)],
                    status: "available", note: "Test fixture", provider: .openMeteo)
            }, onFailure: { _, _ in XCTFail("Disabled primary must not fail") })
        XCTAssertEqual(primaryCalls, 0)
        XCTAssertEqual(backupCalls, 1)
        XCTAssertEqual(result.provider, .openMeteo)
        XCTAssertTrue(result.note.contains("dipilih"))
    }
    func testFailureOfSelectedWeatherProviderStaysUnknown() async throws {
        var failed: [NativeTripWeatherProvider] = []
        let result = try await NativeTripWeatherFallback.resolve(
            pointID: "C", primaryEnabled: false,
            primary: {
                XCTFail("WeatherKit must not be called")
                throw NativeTripWeatherFailure.invalidResponse
            },
            backup: { throw NativeTripWeatherFailure.http(503) },
            onFailure: { provider, _ in failed.append(provider) })
        XCTAssertEqual(failed, [.openMeteo])
        XCTAssertTrue(result.hours.isEmpty)
        XCTAssertEqual(result.status, "unavailable")
    }
    func testSameNamedBranchesRemainAmbiguous() {
        let matches = [
            NativeTripMatch(
                id: "one", name: "Kopi A", address: "Cipete, Jakarta", latitude: -6.27, longitude: 106.80),
            NativeTripMatch(
                id: "two", name: "Kopi A", address: "Kemang, Jakarta", latitude: -6.26, longitude: 106.81),
        ]
        let point = NativeTripPoint(
            id: "A", title: "Kopi A", query: "Kopi A", searchRegion: NativeTripJakarta.region)
        XCTAssertNil(
            NativeTripLocationSelection.automaticMatch(
                matches, point: point, context: NativeTripJakarta.context))
    }
    func testProfileSurvivesStorageRoundTripAndAcceptsEndOnlyProjection() throws {
        let store = repository()
        let draft = NativeTripDraft.jakartaFivePlaces()
        _ = try store.commit(.init(draft: draft), expected: nil)
        XCTAssertEqual(try store.load().session?.draft, draft)
        var endOnly = draft
        endOnly.stops = []
        XCTAssertNoThrow(try endOnly.validate(allowNoStops: true))
        XCTAssertThrowsError(try endOnly.validate())
    }
    func testLegacyBulkLookupIsBlockedBeforeAnyProviderWork() {
        let value = model(repository())
        value.useExample()
        value.resolveMissing()
        XCTAssertNotNil(value.error)
        XCTAssertFalse(value.isBusy)
        XCTAssertTrue(value.searchAttempts.isEmpty)
    }
    func testOldActiveTripCannotReplanOutsideCurrentScopeButFactsRemain() throws {
        let store = repository()
        var old = NativeTripActiveSimulation.report()
        old.simulationKind = nil
        let state = try NativeTripActiveTrip.start(report: old, at: old.draft.departure)
        _ = try store.commit(
            .init(draft: old.draft, acceptedReport: old, activeTrip: state), expected: nil)
        let value = NativeTripActiveController(
            store: store,
            logs: .init(directory: store.directory.appendingPathComponent("logs")),
            clock: { old.draft.departure })
        value.requestReplan(anchorConfirmed: true)
        XCTAssertNotNil(value.error)
        XCTAssertFalse(value.isBusy)
        XCTAssertEqual(value.active?.visits.map(\.status), state.visits.map(\.status))
        XCTAssertEqual(try store.load().session?.activeTrip?.inputRevision, 0)
    }

    func testDuplicateEndpointIdentityCannotHideAnOutsideStop() {
        var draft = NativeTripDraft.jakartaFivePlaces()
        draft.stops[0].point.id = draft.origin.id
        draft.stops[0].point.latitude = -6.402
        draft.stops[0].point.longitude = 106.794
        XCTAssertThrowsError(try draft.validate())
    }

    func testSingleNearbyStreetIsNotAutomaticallyChosenForRequestedVenue() {
        let point = NativeTripPoint(
            id: "glodok", title: "Pasar Glodok", query: "Pasar Glodok",
            searchRegion: NativeTripJakarta.region)
        let street = NativeTripMatch(
            id: "street", name: "Jalan Pasar Glodok Selatan", address: "Jakarta",
            latitude: -6.1434347, longitude: 106.815066)
        XCTAssertNil(
            NativeTripLocationSelection.automaticMatch(
                [street], point: point,
                context: NativeTripJakarta.context, requireExactName: true))
        var venue = street
        venue.name = "Pasar Glodok"
        XCTAssertNotNil(
            NativeTripLocationSelection.automaticMatch(
                [venue], point: point,
                context: NativeTripJakarta.context, requireExactName: true))
    }

    func testJakartaQueryAvoidsCountrySuffixThatReturnedOnlyTheCityInLiveSearch() {
        var draft = NativeTripDraft.jakarta()
        draft.searchContext = "Jakarta, Indonesia"
        let point = NativeTripPoint(id: "oldtown", title: "Kota Tua", query: "Kota Tua")
        XCTAssertEqual(draft.searchQuery(for: point), "Kota Tua, Jakarta")
        XCTAssertEqual(draft.searchQuery(for: point, using: "Kota Tua Jakarta"), "Kota Tua Jakarta")
    }

}
