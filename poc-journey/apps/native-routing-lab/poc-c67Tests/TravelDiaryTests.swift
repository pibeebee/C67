import CoreLocation
import XCTest
@testable import poc_c67

@MainActor final class TravelDiaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_497_600)
    private var pin: DiaryPin { DiaryPin() }

    private func sample(offset: Double = 0, accuracy: Double = 5, age: TimeInterval = 0) -> CLLocation {
        CLLocation(coordinate: .init(latitude: pin.latitude + offset, longitude: pin.longitude),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                   timestamp: now.addingTimeInterval(-age))
    }

    func testInsideAndOutsideAreDistinct() {
        XCTAssertTrue(DiaryPresencePolicy.evaluate(sample(), pin: pin, precise: true, now: now).canAddPhoto)
        guard case .outside = DiaryPresencePolicy.evaluate(sample(offset: 0.004), pin: pin, precise: true, now: now) else {
            return XCTFail("A location about 440 m away must be outside a 100 m pin")
        }
    }

    func testBorderDoesNotUnlockWhenAccuracyCircleCrossesRadius() {
        let edge = sample(offset: 0.00085, accuracy: 15)
        guard case .uncertain = DiaryPresencePolicy.evaluate(edge, pin: pin, precise: true, now: now) else {
            return XCTFail("Border uncertainty must not unlock upload")
        }
    }

    func testStaleFutureMissingAndInvalidFixCannotUnlock() {
        for point in [sample(age: 6), sample(age: -120), sample(accuracy: -1), sample(accuracy: 150)] {
            XCTAssertFalse(DiaryPresencePolicy.evaluate(point, pin: pin, precise: true, now: now).canAddPhoto)
        }
        XCTAssertFalse(DiaryPresencePolicy.evaluate(nil, pin: pin, precise: true, now: now).canAddPhoto)
        let invalid = CLLocation(coordinate: .init(latitude: 100, longitude: 0), altitude: 0,
                                 horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now)
        XCTAssertFalse(DiaryPresencePolicy.evaluate(invalid, pin: pin, precise: true, now: now).canAddPhoto)
    }

    func testReducedAccuracyCannotUnlockEvenAtPinCenter() {
        XCTAssertFalse(DiaryPresencePolicy.evaluate(sample(), pin: pin, precise: false, now: now).canAddPhoto)
    }

    func testUploadCannotReusePreTapArrivalFix() {
        XCTAssertTrue(DiaryPresencePolicy.evaluate(sample(age: 1), pin: pin, precise: true, now: now).canAddPhoto)
        XCTAssertFalse(DiaryPresencePolicy.permitsUpload(sample(age: 1), pin: pin, precise: true, requestedAt: now, now: now))
        XCTAssertTrue(DiaryPresencePolicy.permitsUpload(sample(), pin: pin, precise: true, requestedAt: now, now: now))
    }

    func testLeavingAfterArrivalRejectsUploadAndWritesNothing() throws {
        let store = DiaryStore(url: nil)
        XCTAssertTrue(DiaryPresencePolicy.evaluate(sample(), pin: store.pin, precise: true, now: now).canAddPhoto)
        XCTAssertThrowsError(try store.addPhoto(Data([1]), name: "Raka", sample: sample(offset: 0.004), precise: true,
                                                pinID: store.pin.id, requestedAt: now, simulated: false, now: now))
        XCTAssertTrue(store.footprints.isEmpty)
    }

    func testLocalFootprintSurvivesReloadWithItsEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "diary.json")
        let store = DiaryStore(url: url)
        let photo = Data([1, 2, 3])
        let result = try store.addPhoto(photo, name: "Raka", sample: sample(), precise: true,
                                        pinID: store.pin.id, requestedAt: now, simulated: true, now: now)
        let reopened = DiaryStore(url: url)
        XCTAssertEqual(reopened.footprints.first?.id, result.id)
        XCTAssertEqual(reopened.footprints.first?.photo, photo)
        XCTAssertEqual(reopened.footprints.first?.measuredAt, now)
        XCTAssertEqual(reopened.footprints.first?.requestedAt, now)
        XCTAssertEqual(reopened.footprints.first?.simulated, true)
    }

    func testLocationOrRadiusChangeNeverMovesOldFootprints() throws {
        let store = DiaryStore(url: nil)
        let firstID = store.pin.id
        try store.addPhoto(Data([1]), name: "Raka", sample: sample(), precise: true,
                           pinID: firstID, requestedAt: now, simulated: false, now: now)
        var edited = store.pin
        edited.latitude += 0.01
        try store.savePin(edited)
        XCTAssertNotEqual(store.pin.id, firstID)
        XCTAssertTrue(store.footprints.isEmpty)
        XCTAssertEqual(store.archive.footprints.count, 1)
        XCTAssertEqual(store.archive.footprints[0].pinID, firstID)
        XCTAssertThrowsError(try store.addPhoto(Data([2]), name: "Raka", sample: sample(), precise: true,
                                                pinID: firstID, requestedAt: now, simulated: false, now: now))
    }

    func testStoryEditKeepsSamePinIdentity() throws {
        let store = DiaryStore(url: nil)
        let firstID = store.pin.id
        var edited = store.pin
        edited.story = "Cerita baru"
        try store.savePin(edited)
        XCTAssertEqual(store.pin.id, firstID)
    }

    func testWriteFailureDoesNotPublishSuccessfulFootprint() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "diary.json")
        let store = DiaryStore(url: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.addPhoto(Data([1]), name: "Raka", sample: sample(), precise: true,
                                                pinID: store.pin.id, requestedAt: now, simulated: false, now: now))
        XCTAssertTrue(store.footprints.isEmpty)
    }

    func testUnreadableFileIsPreservedInsteadOfReset() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("not a diary".utf8)
        try data.write(to: url)
        let store = DiaryStore(url: url)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.savePin(pin))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testInvalidPinAndEmptyPhotoAreRejected() {
        let store = DiaryStore(url: nil)
        var invalid = pin
        invalid.radius = .infinity
        XCTAssertThrowsError(try store.savePin(invalid))
        XCTAssertThrowsError(try store.addPhoto(Data(), name: "Raka", sample: sample(), precise: true,
                                                pinID: store.pin.id, requestedAt: now, simulated: false, now: now))
        XCTAssertThrowsError(try store.addPhoto(Data([1]), name: "  ", sample: sample(), precise: true,
                                                pinID: store.pin.id, requestedAt: now, simulated: false, now: now))
        XCTAssertTrue(store.footprints.isEmpty)
    }

    func testPhotoNormalizationRejectsNonImageAndAcceptsPhoto() throws {
        XCTAssertThrowsError(try DiaryPhotoCodec.normalized(Data("not an image".utf8)))
        let result = try DiaryPhotoCodec.normalized(DiaryPhotoCodec.fixture())
        XCTAssertFalse(result.isEmpty)
    }
}
