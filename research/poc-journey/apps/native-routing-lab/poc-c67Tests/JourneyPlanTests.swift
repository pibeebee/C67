import XCTest
import EventKit
import CloudKit
@testable import poc_c67

@MainActor private final class PlanTransportStub: JourneyPlanTransport {
    var writes: [(JourneyPlan, CloudReference)] = []
    var remote: JourneyPlan?
    var fail = false
    var unavailableZone: String?
    var onPublish: (() -> Void)?
    var onFetch: (() -> Void)?
    func publishPlan(_ plan: JourneyPlan, to ref: CloudReference) async throws {
        if fail { throw POCError.message("offline") }
        if unavailableZone == ref.zoneName { throw CKError(.zoneNotFound) }
        writes.append((plan, ref)); onPublish?()
    }
    func fetchPlan(_ ref: CloudReference) async throws -> JourneyPlan? {
        onFetch?()
        if fail { throw POCError.message("offline") }
        return remote
    }
}

@MainActor final class JourneyPlanTests: XCTestCase {
    func activity(title: String = "Kembali ke bus", located: Bool = true) -> TourActivity {
        TourActivity(title: title, start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_003_600), timeZoneID: "Asia/Jakarta", notes: "Parkir B", place: located ? TourPlace(name: "Parkir B", latitude: -6.17, longitude: 106.82) : nil)
    }
    func store() throws -> SessionStore { try SessionStore(container: SessionStore.container(inMemory: true)) }
    func leader(_ store: SessionStore) throws -> [CloudReference] {
        let cloud = CloudLocationChannel()
        let refs = [cloud.makeReference(runID: store.state.runID, participantID: "TL"), cloud.makeReference(runID: store.state.runID, participantID: "TL")]
        try store.commit {
            $0.mode = .real; $0.qrMembers = []
            $0.leaderShares = refs.enumerated().map { LeaderShare(accountRecord: "account\($0.offset)", reference: $0.element) }
        }
        return refs
    }
    func participant(_ store: SessionStore) throws -> CloudReference {
        let ref = CloudLocationChannel().makeReference(runID: store.state.runID, participantID: "TL")
        try store.commit {
            $0.mode = .real; $0.leaderBinding = ref
            $0.joinedQR = JoinedJourney(journey: "Tur", leader: "TL", leaderRecord: "_TL", participantID: UUID().uuidString, participantName: "Ayu")
        }
        return ref
    }
    func testOptionalPlanAndReceiptsPreserveOldSnapshotAndStableFallback() throws {
        var state = RunState()
        state.meetingPoint = MeetingPointSnapshot(latitude: -6, longitude: 106, radius: 100)
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(RunState.self, from: data)
        XCTAssertNil(restored.journeyPlan); XCTAssertNil(restored.calendarExports)
        XCTAssertEqual(restored.effectivePlan, restored.effectivePlan)
        XCTAssertEqual(restored.effectivePlan.meetingPoint, state.meetingPoint)
    }
    func testActivityValidatesDatesLimitsCoordinatesAndTimezone() {
        var a = activity(); XCTAssertTrue(a.valid)
        a.end = a.start; XCTAssertFalse(a.valid)
        a = activity(); a.title = " \n"; XCTAssertFalse(a.valid)
        a = activity(); a.timeZoneID = "Wrong/Zone"; XCTAssertFalse(a.valid)
        a = activity(); a.notes = String(repeating: "a", count: 2001); XCTAssertFalse(a.valid)
        a = activity(); a.place?.latitude = 91; XCTAssertFalse(a.valid)
        XCTAssertTrue(activity(located: false).valid)
    }
    func testSaveUpdateDeleteAndReloadDoNotChangeAttendance() throws {
        let container = try SessionStore.container(inMemory: true)
        let store = try SessionStore(container: container)
        let counts = store.state.sessions[0].counts
        var a = activity()
        try store.commit { try $0.saveActivity(a) }
        let revision = store.state.effectivePlan.revision
        a.title = "Berkumpul bus"
        try store.commit { try $0.saveActivity(a) }
        XCTAssertEqual(store.state.effectivePlan.activities.count, 1)
        XCTAssertGreaterThan(store.state.effectivePlan.revision, revision)
        XCTAssertEqual(try SessionStore(container: container).state.effectivePlan.activities[0].title, a.title)
        try store.commit { try $0.deleteActivity(a.id) }
        XCTAssertTrue(store.state.effectivePlan.activities.isEmpty)
        XCTAssertEqual(store.state.sessions[0].counts, counts)
    }
    func testFailedSavePreservesPlanAndMeetingPoint() throws {
        let store = try store(); let a = activity()
        store.failNextSave = true
        XCTAssertThrowsError(try store.commit { try $0.saveActivity(a) })
        XCTAssertNil(store.state.journeyPlan)
        XCTAssertNil(store.state.meetingPoint)
    }
    func testActivationUpdatesMeetingOnlyAndEditingActiveLocationPropagates() throws {
        var state = RunState(); var a = activity()
        let counts = state.sessions[0].counts
        try state.saveActivity(a); try state.activateActivity(a.id)
        XCTAssertEqual(state.meetingPoint, a.place?.meeting)
        XCTAssertEqual(state.effectivePlan.activeActivityID, a.id)
        XCTAssertEqual(state.sessions[0].counts, counts)
        a.place?.name = "Parkir C"; a.place?.longitude = 107
        try state.saveActivity(a)
        XCTAssertEqual(state.meetingPoint?.longitude, 107)
        XCTAssertEqual(state.effectivePlan.meetingName, "Parkir C")
        a.place = nil; try state.saveActivity(a)
        XCTAssertNil(state.meetingPoint); XCTAssertNil(state.effectivePlan.activeActivityID)
    }
    func testDeletingActiveActivityClearsMeetingAndManualPointUnlinksActivity() throws {
        var state = RunState(); let a = activity()
        try state.saveActivity(a); try state.activateActivity(a.id)
        try state.setMeetingPoint(MeetingPointSnapshot(latitude: 1, longitude: 2, radius: 300), name: "Titik lain")
        XCTAssertNil(state.effectivePlan.activeActivityID)
        try state.deleteActivity(a.id)
        XCTAssertEqual(state.meetingPoint?.latitude, 1)
        try state.saveActivity(a); try state.activateActivity(a.id); try state.deleteActivity(a.id)
        XCTAssertNil(state.meetingPoint)
    }
    func testCannotActivateUnlocatedOrMissingActivity() throws {
        var state = RunState(); let a = activity(located: false)
        try state.saveActivity(a)
        XCTAssertThrowsError(try state.activateActivity(a.id))
        XCTAssertThrowsError(try state.activateActivity(UUID()))
    }
    func testParticipantCannotMutateScheduleOrMeetingPoint() throws {
        let store = try store(); _ = try participant(store)
        XCTAssertThrowsError(try store.commit { try $0.saveActivity(activity()) })
        XCTAssertThrowsError(try store.commit { try $0.setMeetingPoint(nil, name: nil) })
        XCTAssertNil(store.state.journeyPlan)
    }
    func testPlanRejectsWrongRunDuplicateIDsOversizedAndInvalidActivePoint() throws {
        let run = UUID(); let a = activity()
        var plan = JourneyPlan(runID: run, activities: [a])
        XCTAssertThrowsError(try plan.validate(for: UUID()))
        plan.activities.append(a); XCTAssertThrowsError(try plan.validate(for: run))
        plan.activities = [a]; plan.activeActivityID = a.id
        XCTAssertThrowsError(try plan.validate(for: run))
        plan.activeActivityID = nil; plan.activities = (0 ..< 51).map { activity(title: "Kegiatan \($0)") }
        XCTAssertThrowsError(try plan.validate(for: run))
        plan.activities = (0 ..< 50).map { index in
            var item = activity(title: "Kegiatan \(index)"); item.notes = String(repeating: "😀", count: 2000); return item
        }
        XCTAssertThrowsError(try plan.validate(for: run))
    }
    func testReceiveUpdatesClearAndDoesNotRollbackOrAcceptRevisionConflict() throws {
        var state = RunState(); let a = activity()
        var remote = JourneyPlan(runID: state.runID, revision: 4, activities: [a], activeActivityID: a.id, meetingPoint: a.place?.meeting, meetingName: a.place?.name)
        try state.receivePlan(remote)
        XCTAssertNotNil(state.meetingPoint)
        var old = remote; old.revision = 3; old.activities[0].notes = "Versi lama"
        try state.receivePlan(old); XCTAssertEqual(state.journeyPlan, remote)
        var conflict = remote; conflict.activities[0].notes = "different"
        XCTAssertThrowsError(try state.receivePlan(conflict))
        remote.revision = 5; remote.activities = []; remote.activeActivityID = nil; remote.meetingPoint = nil; remote.meetingName = nil
        try state.receivePlan(remote)
        XCTAssertNil(state.meetingPoint); XCTAssertTrue(state.effectivePlan.activities.isEmpty)
    }
    func testPublishFanoutAndRetryKeepsPerRecipientRevisionAcknowledgement() async throws {
        let store = try store(); let refs = try leader(store)
        try store.commit { try $0.saveActivity(activity()) }
        let transport = PlanTransportStub(); let sync = JourneyPlanSync(store: store, transport: transport)
        await sync.publish(); XCTAssertEqual(transport.writes.count, 2)
        XCTAssertEqual(Set(transport.writes.map { $0.1.zoneName }), Set(refs.map(\.zoneName)))
        await sync.publish(); XCTAssertEqual(transport.writes.count, 2)
        transport.fail = true
        try store.commit { try $0.setMeetingPoint(nil, name: nil) }
        await sync.publish(); XCTAssertTrue(sync.status.contains("0/2"))
        transport.fail = false; await sync.publish()
        XCTAssertEqual(transport.writes.count, 4)
        XCTAssertTrue(sync.status.contains("penerimaan peserta belum dikonfirmasi"))
    }
    func testNewRecipientReceivesUnchangedPlanWithoutResendingOtherChannels() async throws {
        let store = try store(); _ = try leader(store)
        let transport = PlanTransportStub(); let sync = JourneyPlanSync(store: store, transport: transport)
        await sync.publish()
        let extra = CloudLocationChannel().makeReference(runID: store.state.runID, participantID: "TL")
        try store.commit { $0.leaderShares?.append(LeaderShare(accountRecord: "new", reference: extra)) }
        await sync.publish()
        XCTAssertEqual(transport.writes.count, 3); XCTAssertEqual(transport.writes.last?.1, extra)
    }
    func testFetchPersistsPlanWithoutGPSAndOfflinePreservesCache() async throws {
        let store = try store(); _ = try participant(store)
        let transport = PlanTransportStub()
        transport.remote = JourneyPlan(runID: store.state.runID, revision: 7, activities: [activity()])
        let sync = JourneyPlanSync(store: store, transport: transport)
        await sync.fetch(); XCTAssertEqual(store.state.effectivePlan.revision, 7)
        XCTAssertNotNil(sync.lastReceivedAt)
        let cached = store.state.journeyPlan; transport.fail = true
        await sync.fetch(); XCTAssertEqual(store.state.journeyPlan, cached); XCTAssertTrue(sync.status.contains("mungkin lama"))
        transport.fail = false; transport.remote = nil
        await sync.fetch(); XCTAssertEqual(store.state.journeyPlan, cached)
    }
    func testLateFetchAfterLeavingShareCannotRestoreData() async throws {
        let store = try store(); _ = try participant(store)
        let transport = PlanTransportStub(); transport.remote = JourneyPlan(runID: store.state.runID, revision: 5, activities: [activity()])
        transport.onFetch = { try? store.commit { $0.leaderBinding = nil } }
        let sync = JourneyPlanSync(store: store, transport: transport)
        await sync.fetch(); XCTAssertNil(store.state.journeyPlan)
    }
    func testCalendarMappingPreservesTitleTimeTimezonePlaceAndNotes() {
        let a = activity(); let store = EKEventStore()
        let event = CalendarEventSheet.makeEvent(CalendarDraft(activity: a, journey: "Tur Jakarta", runID: UUID()), store: store)
        XCTAssertEqual(event.title, a.title); XCTAssertEqual(event.startDate, a.start); XCTAssertEqual(event.endDate, a.end)
        XCTAssertEqual(event.timeZone?.identifier, "Asia/Jakarta")
        XCTAssertEqual(event.structuredLocation?.geoLocation?.coordinate.latitude, a.place?.latitude)
        XCTAssertEqual(event.location, "Parkir B"); XCTAssertTrue(event.notes?.contains("Tur Jakarta") == true)
        XCTAssertTrue(event.notes?.contains("tidak otomatis") == true)
    }
    func testCalendarReceiptDetectsChangesAndIsDeviceLocalOnly() throws {
        var a = activity(); let original = a.calendarFingerprint
        a.notes = "Catatan baru"; XCTAssertNotEqual(a.calendarFingerprint, original)
        let state = RunState(); let encoded = String(data: try JSONEncoder().encode(state.effectivePlan), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("calendarExports"))
    }
    func testEditingDuringPublishRemainsPendingUntilNextRevisionReachesEveryChannel() async throws {
        let store = try store(); _ = try leader(store)
        try store.commit { try $0.saveActivity(activity()) }
        let transport = PlanTransportStub(); let sync = JourneyPlanSync(store: store, transport: transport)
        transport.onPublish = {
            transport.onPublish = nil
            try? store.commit { try $0.setMeetingPoint(nil, name: nil) }
        }
        await sync.publish()
        XCTAssertTrue(sync.status.contains("Coba sinkronkan lagi"))
        let revision = store.state.effectivePlan.revision
        await sync.publish()
        XCTAssertEqual(transport.writes.suffix(2).map { $0.0.revision }, [revision, revision])
    }
    func testFailedPersistOfReceivedPlanKeepsPreviousSnapshotAndRetryWorks() async throws {
        let store = try store(); _ = try participant(store)
        let transport = PlanTransportStub(); transport.remote = JourneyPlan(runID: store.state.runID, revision: 3, activities: [activity()])
        let sync = JourneyPlanSync(store: store, transport: transport)
        store.failNextSave = true; await sync.fetch()
        XCTAssertNil(store.state.journeyPlan); XCTAssertNil(sync.lastReceivedAt)
        await sync.fetch(); XCTAssertEqual(store.state.journeyPlan?.revision, 3)
    }

    func testPartialOrRevokedChannelDoesNotBlockOtherParticipants() async throws {
        let store = try store(); let refs = try leader(store)
        let transport = PlanTransportStub(); transport.unavailableZone = refs[0].zoneName
        let sync = JourneyPlanSync(store: store, transport: transport)
        await sync.publish()
        XCTAssertEqual(transport.writes.count, 1)
        XCTAssertEqual(transport.writes.first?.1, refs[1])
        XCTAssertTrue(sync.status.contains("1/2"))
    }

}
