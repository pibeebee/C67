import XCTest

final class POCFlowTests: XCTestCase {
    @MainActor func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launch(); return app
    }
    @MainActor func find(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        if id == "counts" {
            for _ in 0 ..< 8 {
                if element.exists { return element }
                app.collectionViews.firstMatch.swipeDown(velocity: .fast)
            }
        }
        let fixedControl = ["open-demo", "open-setup", "review-session", "next-session"].contains(id)
        let readOnly = ["counts", "location-freshness", "start-sharing"].contains(id)
        func visible() -> Bool {
            if readOnly { return element.exists }
            guard element.exists, element.isHittable else { return false }
            // SwiftUI can expose a clipped row as hittable behind a bottom inset.
            return fixedControl || !id.hasPrefix("participant-") || (element.frame.minY >= 100 && element.frame.maxY <= app.frame.maxY - 170)
        }
        for _ in 0 ..< 9 {
            if visible() { return element }
            app.swipeUp()
        }
        for _ in 0 ..< 9 {
            if visible() { return element }
            app.swipeDown()
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Missing \(id)"; shot.lifetime = .keepAlways; add(shot)
        XCTFail("Kontrol tidak ditemukan: \(id).\n\(app.debugDescription)"); return element
    }
    @MainActor func testSimulationDoesNotVerifyAndManualCheckWorks() {
        let app = launch()
        find("simulate-near", in: app).tap()
        XCTAssertTrue(find("counts", in: app).label.contains("V 0"))
        find("participant-P01", in: app).tap()
        find("verify-P01", in: app).tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(find("counts", in: app).label.contains("V 1"))
        find("simulate-stale", in: app).tap()
        XCTAssertTrue(find("location-freshness", in: app).label.contains("Kedaluwarsa"))
    }
    @MainActor func testNotedClosureAndNextSessionReset() {
        let app = launch()
        find("participant-P03", in: app).tap()
        find("verify-P03", in: app).tap()
        app.navigationBars.buttons.firstMatch.tap()
        find("review-session", in: app).tap()
        let note = find("closure-note", in: app)
        note.tap(); note.typeText("Pengujian pengecualian")
        find("close-with-note", in: app).tap()
        find("next-session", in: app).tap()
        XCTAssertTrue(find("counts", in: app).label.contains("V 0"))
        XCTAssertTrue(find("counts", in: app).label.contains("U 4"))
    }
    @MainActor func testManualCheckAtAccessibilityTextSize() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--large-text"]
        app.launch()
        find("participant-P01", in: app).tap()
        find("verify-P01", in: app).tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(find("counts", in: app).label.contains("V 1"))
    }
    @MainActor func testDemoScenarioRequiresConfirmationAndShowsCorrectCounts() {
        let app = launch()
        find("open-demo", in: app).tap()
        find("demo-regroup", in: app).tap()
        app.buttons["Batal"].tap()
        app.buttons["Selesai"].tap()
        XCTAssertTrue(find("counts", in: app).label.contains("V 0"))
        find("open-demo", in: app).tap()
        find("demo-regroup", in: app).tap()
        app.buttons["Muat skenario demo"].tap()
        XCTAssertTrue(find("counts", in: app).label.contains("E 3"))
        XCTAssertTrue(find("counts", in: app).label.contains("V 2"))
        XCTAssertTrue(find("counts", in: app).label.contains("O 1"))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Demo regroup dashboard"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor func testParticipantActionSheetKeepsFollowUpIndependent() {
        let app = launch()
        find("participant-P01", in: app).tap()
        find("open-follow-up", in: app).tap()
        let reason = find("action-reason", in: app)
        reason.tap(); reason.typeText("Belum kembali")
        find("save-participant-action", in: app).tap()
        find("verify-P01", in: app).tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(find("counts", in: app).label.contains("V 1"))
        XCTAssertTrue(find("counts", in: app).label.contains("O 1"))
    }
    @MainActor func testParticipantGuideDoesNotAllowUnconsentedStart() {
        let app = launch()
        app.tabBars.buttons["Peserta"].tap()
        XCTAssertTrue(app.buttons["open-participant-qr"].exists)
        XCTAssertFalse(app.textFields["join-run-id"].exists)
        XCTAssertFalse(app.buttons["start-sharing"].exists)
        XCTAssertFalse(app.switches["sharing-consent"].exists)
        XCTAssertFalse(app.staticTexts["Mulai saat siap"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Participant QR only"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor func testQRJourneyCreationIsExplicitAndRosterStartsEmpty() {
        let app = launch()
        find("open-leader-qr", in: app).tap()
        let name = find("qr-leader-name", in: app); name.tap(); name.typeText("Budi")
        find("create-qr-journey", in: app).tap()
        app.alerts.buttons["Batal"].tap()
        XCTAssertTrue(app.textFields["qr-leader-name"].exists)
        find("create-qr-journey", in: app).tap()
        app.alerts.buttons["Ganti & buat perjalanan"].tap()
        XCTAssertTrue(app.buttons["show-journey-qr"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "QR leader invitation setup"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Selesai"].tap()
        XCTAssertTrue(find("counts", in: app).label.contains("E 0"))
        XCTAssertTrue(find("counts", in: app).label.contains("V 0"))
    }
    @MainActor func testInvalidQRDoesNotAllowJoining() {
        let app = launch(); app.tabBars.buttons["Peserta"].tap()
        find("open-participant-qr", in: app).tap()
        app.buttons["Masukkan isi QR secara manual"].tap()
        let input = find("qr-manual-input", in: app); input.tap(); input.typeText("c67://join/invalid")
        find("read-qr-invite", in: app).tap()
        XCTAssertTrue(find("operation-error", in: app).label.contains("bukan undangan"))
        XCTAssertFalse(app.buttons["join-qr-journey"].exists)
    }
    @MainActor func testQRJoinShowsDestinationAndRequiresConsent() throws {
        let app = launch(); app.tabBars.buttons["Peserta"].tap()
        find("open-participant-qr", in: app).tap()
        let name = find("qr-participant-name", in: app); name.tap(); name.typeText("Ayu")
        app.buttons["Masukkan isi QR secara manual"].tap()
        let payload: [String: Any] = ["version": 3, "id": UUID().uuidString, "runID": UUID().uuidString, "journey": "Tur Jakarta", "leader": "Budi", "leaderRecord": "_fixture", "token": String(repeating: "a", count: 64), "publicKey": Data(repeating: 1, count: 32).base64EncodedString(), "expiresAt": Date.now.addingTimeInterval(300).timeIntervalSinceReferenceDate]
        let encoded = "c67://join/" + (try JSONSerialization.data(withJSONObject: payload)).base64EncodedString()
        let input = find("qr-manual-input", in: app); input.tap(); input.typeText(encoded)
        find("read-qr-invite", in: app).tap()
        XCTAssertTrue(app.staticTexts["Tur Jakarta"].exists)
        XCTAssertTrue(find("join-qr-journey", in: app).isEnabled)
        XCTAssertFalse(app.switches["qr-sharing-consent"].exists)
        XCTAssertFalse(app.steppers["participant-sharing-duration"].exists)
        find("join-qr-journey", in: app).tap()
        XCTAssertTrue(app.navigationBars["Persetujuan lokasi"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Budi"].exists)
        XCTAssertTrue(app.steppers["participant-sharing-duration"].exists)
        XCTAssertTrue(app.switches["participant-sharing-background"].exists)
        XCTAssertTrue(find("confirm-participant-sharing", in: app).isEnabled)
        XCTAssertTrue(app.staticTexts["participant-consent-summary"].label.contains("30 menit"))
        app.buttons["participant-sharing-duration-Increment"].tap()
        XCTAssertTrue(app.staticTexts["participant-consent-summary"].label.contains("35 menit"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Participant consent popup v41"; shot.lifetime = .keepAlways; add(shot)
        find("cancel-participant-consent", in: app).tap()
        XCTAssertTrue(app.buttons["join-qr-journey"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["qr-guest-status"].exists)
        XCTAssertFalse(app.buttons["confirm-participant-sharing"].exists)
        // Cancellation does not retain consent: the next attempt presents the popup again.
        find("join-qr-journey", in: app).tap()
        XCTAssertTrue(app.navigationBars["Persetujuan lokasi"].waitForExistence(timeout: 3))
    }
    @MainActor func testManualPairingLivesInLab() {
        let app = launch(); app.tabBars.buttons["Lab"].tap()
        find("open-manual-pairing", in: app).tap()
        XCTAssertTrue(app.textFields["join-run-id"].exists)
        XCTAssertTrue(find("reset-fixture", in: app).exists)
        XCTAssertFalse(app.buttons["open-participant-qr"].exists)
    }
    @MainActor func testLeaderSettingsOnlyContainMeetingPoint() {
        let app = launch(); find("open-setup", in: app).tap()
        XCTAssertTrue(app.buttons["pick-meeting-point"].exists)
        XCTAssertFalse(app.textFields["Latitude"].exists)
        XCTAssertTrue(app.buttons["Simpan meeting point"].exists)
        XCTAssertFalse(app.buttons["Buat run baru…"].exists)
        XCTAssertFalse(app.buttons["Salin Run ID"].exists)
        XCTAssertFalse(app.buttons["create-qr-journey"].exists)
    }
    @MainActor func testStoredParticipantShowsStopAndConsentOnlyOnResume() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-resume-fixture"]
        app.launch(); app.tabBars.buttons["Peserta"].tap()
        XCTAssertTrue(app.buttons["stop-sharing"].exists)
        XCTAssertTrue(app.buttons["resume-sharing"].exists)
        XCTAssertFalse(app.buttons["open-participant-qr"].exists)
        XCTAssertFalse(app.switches["sharing-consent"].exists)
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "Participant stored connection"; before.lifetime = .keepAlways; add(before)
        find("resume-sharing", in: app).tap()
        XCTAssertFalse(app.switches["sharing-consent"].exists)
        XCTAssertTrue(app.steppers["participant-sharing-duration"].exists)
        XCTAssertFalse(find("start-sharing", in: app).isEnabled)
        XCTAssertFalse(app.buttons["open-participant-qr"].exists)
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "Resume consent modal"; after.lifetime = .keepAlways; add(after)
        find("cancel-participant-consent", in: app).tap()
        app.tabBars.buttons["Lab"].tap()
        find("open-manual-pairing", in: app).tap()
        XCTAssertFalse(app.textFields["join-run-id"].exists)
        XCTAssertFalse(find("reset-fixture", in: app).isEnabled)
    }
    @MainActor func mapDemo() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--demo-preview"]; app.launch(); return app
    }
    @MainActor func testGroupMapShowsAllPinsSelectionAndCameraControls() {
        let app = mapDemo()
        find("open-location", in: app).tap()
        XCTAssertTrue(app.staticTexts["map-point-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map-point-count"].label.contains("4 lokasi peserta"))
        let map = app.maps.firstMatch
        XCTAssertTrue(map.exists)
        map.pinch(withScale: 1.5, velocity: 1)
        map.swipeLeft()
        find("map-style", in: app).tap()
        find("map-fit-all", in: app).tap()
        find("map-list", in: app).tap()
        XCTAssertTrue(app.buttons["map-person-P01"].exists)
        XCTAssertTrue(app.buttons["map-person-P03"].exists)
        app.buttons["map-person-P02"].tap()
        XCTAssertTrue(app.staticTexts["map-selected-name"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["map-selected-name"].label.contains("Budi"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Interactive group map"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testParticipantMapContainsLeaderAndSelfOnly() {
        let app = mapDemo(); app.tabBars.buttons["Peserta"].tap()
        find("open-participant-map", in: app).tap()
        find("map-list", in: app).tap()
        XCTAssertTrue(app.buttons["map-person-TL"].exists)
        XCTAssertTrue(app.buttons["map-person-YOU"].exists)
        XCTAssertFalse(app.buttons["map-person-P02"].exists)
        app.buttons["map-person-TL"].tap()
        XCTAssertTrue(app.staticTexts["map-selected-name"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Participant leader map"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testLeaderLocationRequiresConsentAndConnectedParticipants() {
        let app = launch(); find("open-leader-sharing", in: app).tap()
        XCTAssertTrue(app.switches["leader-location-consent"].exists)
        XCTAssertFalse(app.buttons["start-leader-sharing"].isEnabled)
    }
    @MainActor func testMapPinCanBeSelectedDirectly() {
        let app = mapDemo(); find("open-location", in: app).tap()
        let pin = app.buttons["map-pin-P01"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        XCTAssertTrue(app.staticTexts["map-selected-name"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["map-selected-name"].label.contains("Ayu"))
        find("map-fit-all", in: app).tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "All group map pins overview"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testDefaultMapHasNoMeetingPointAndSettingsCanSaveAndClearIt() {
        let app = launch()
        find("open-location", in: app).tap()
        XCTAssertTrue(app.staticTexts["map-no-meeting-point"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["map-meeting-point"].exists)
        XCTAssertFalse(app.buttons["map-my-location"].isEnabled)
        app.buttons["Selesai"].tap()
        find("open-setup", in: app).tap()
        XCTAssertTrue(app.staticTexts["meeting-point-empty"].exists)
        find("pick-meeting-point", in: app).tap()
        XCTAssertFalse(app.buttons["use-picked-location"].isEnabled)
        find("pick-map-center", in: app).tap()
        XCTAssertTrue(app.buttons["use-picked-location"].isEnabled)
        find("use-picked-location", in: app).tap()
        find("save-meeting-point", in: app).tap()
        find("open-location", in: app).tap()
        XCTAssertFalse(app.staticTexts["map-no-meeting-point"].exists)
        XCTAssertTrue(app.buttons["map-meeting-point"].exists)
        app.buttons["Selesai"].tap()
        find("open-setup", in: app).tap()
        find("clear-meeting-point", in: app).tap()
        find("open-location", in: app).tap()
        XCTAssertTrue(app.staticTexts["map-no-meeting-point"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["map-meeting-point"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Map without meeting point v41"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testMyLocationButtonSelectsOwnPinForBothRoles() {
        let app = mapDemo()
        find("open-location", in: app).tap()
        find("map-my-location", in: app).tap()
        XCTAssertTrue(app.staticTexts["map-selected-name"].label.contains("Anda"))
        app.buttons["Selesai"].tap()
        app.tabBars.buttons["Peserta"].tap()
        find("open-participant-map", in: app).tap()
        find("map-my-location", in: app).tap()
        XCTAssertTrue(app.staticTexts["map-selected-name"].label.contains("Anda"))
    }
    @MainActor func testRealMapShowsLocalGPSWithoutStartingSharing() {
        // Simulator location/authorization are configured by the verification command.
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-real-map-fixture"]
        app.launch(); find("open-location", in: app).tap()
        let mine = app.buttons["map-my-location"]
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: mine)
        waitForExpectations(timeout: 20)
        mine.tap()
        XCTAssertTrue(app.staticTexts["map-selected-name"].label.contains("Anda · TL"))
        XCTAssertTrue(app.staticTexts["map-no-meeting-point"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Local Core Location map without sharing v41"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Selesai"].tap()
        find("open-leader-sharing", in: app).tap()
        XCTAssertFalse(app.buttons["start-leader-sharing"].isEnabled)
        XCTAssertFalse(app.buttons["stop-leader-sharing"].exists)
    }
    @MainActor func testItineraryCreateEditDeleteWithoutLocationAndValidation() {
        let app = launch(); find("open-itinerary", in: app).tap()
        find("add-activity", in: app).tap()
        XCTAssertFalse(app.buttons["save-activity"].isEnabled)
        let title = app.textFields["activity-title"]; title.tap(); title.typeText("Makan siang")
        find("save-activity", in: app).tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'activity-row-'")).firstMatch.tap()
        XCTAssertEqual(app.staticTexts["activity-detail-title"].label, "Makan siang")
        XCTAssertFalse(app.buttons["activate-activity"].exists)
        find("edit-activity", in: app).tap()
        let field = app.textFields["activity-notes"]; field.tap(); field.typeText("Menu sayur")
        find("save-activity", in: app).tap()
        XCTAssertTrue(app.staticTexts["Menu sayur"].exists)
        find("delete-activity", in: app).tap(); app.alerts.buttons["Hapus"].tap()
        XCTAssertTrue(app.staticTexts["Belum ada kegiatan"].waitForExistence(timeout: 3))
    }
    @MainActor func testActivityLocationPickerCancelThenSaveDoesNotCreateImplicitMeetingPoint() {
        let app = launch(); find("open-itinerary", in: app).tap(); find("add-activity", in: app).tap()
        let title = app.textFields["activity-title"]; title.tap(); title.typeText("Berkumpul")
        find("activity-pick-location", in: app).tap()
        XCTAssertFalse(app.buttons["use-picked-location"].isEnabled)
        app.navigationBars["Pilih lokasi"].buttons["Batal"].tap()
        XCTAssertFalse(app.staticTexts["activity-place"].exists)
        find("activity-pick-location", in: app).tap(); find("pick-map-center", in: app).tap()
        let pickerShot = XCTAttachment(screenshot: app.screenshot()); pickerShot.name = "Native map point picker v5"; pickerShot.lifetime = .keepAlways; add(pickerShot)
        find("use-picked-location", in: app).tap()
        XCTAssertTrue(app.staticTexts["activity-place"].exists)
        find("save-activity", in: app).tap()
        app.navigationBars.buttons.firstMatch.tap()
        find("open-location", in: app).tap()
        XCTAssertTrue(app.staticTexts["map-no-meeting-point"].exists)
        find("map-list", in: app).tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map-list-activity-'")).firstMatch.exists)
    }
    @MainActor func testDemoActivityMapSelectionAndExplicitActivation() {
        let app = mapDemo(); find("open-itinerary", in: app).tap()
        let overview = XCTAttachment(screenshot: app.screenshot()); overview.name = "Itinerary overview v5"; overview.lifetime = .keepAlways; add(overview)
        find("activity-row-00000000-0000-0000-0000-000000000501", in: app).tap()
        find("activate-activity", in: app).tap(); app.alerts.buttons["Batal"].tap()
        XCTAssertFalse(app.staticTexts["Titik berkumpul aktif"].exists)
        find("activate-activity", in: app).tap(); app.alerts.buttons["Jadikan aktif"].tap()
        XCTAssertTrue(app.staticTexts["Titik berkumpul aktif"].exists)
        find("activity-show-map", in: app).tap()
        XCTAssertTrue(app.staticTexts["map-selected-activity"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["map-selected-activity"].label, "Kembali ke bus")
        find("map-list", in: app).tap()
        find("map-list-activity-00000000-0000-0000-0000-000000000502", in: app).tap()
        XCTAssertEqual(app.staticTexts["map-selected-activity"].label, "Kunjungan museum")
        find("map-activity-detail", in: app).tap()
        let detailTitle = app.staticTexts.matching(identifier: "activity-detail-title").matching(NSPredicate(format: "label == %@", "Kunjungan museum")).firstMatch
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Activity detail from map v5"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testActivityPinCanBeSelectedDirectly() {
        let app = mapDemo(); find("open-itinerary", in: app).tap()
        find("activity-row-00000000-0000-0000-0000-000000000501", in: app).tap()
        find("activity-show-map", in: app).tap()
        let pin = app.buttons["map-activity-00000000-0000-0000-0000-000000000501"]
        XCTAssertTrue(pin.waitForExistence(timeout: 8))
        pin.tap()
        XCTAssertEqual(app.staticTexts["map-selected-activity"].label, "Kembali ke bus")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Rundown and participants map v5"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testParticipantItineraryIsReadOnlyAndCanOpenMap() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-itinerary-participant"]
        app.launch(); app.tabBars.buttons["Peserta"].tap()
        find("open-participant-itinerary", in: app).tap()
        XCTAssertFalse(app.buttons["add-activity"].exists)
        find("activity-row-00000000-0000-0000-0000-000000000501", in: app).tap()
        XCTAssertFalse(app.buttons["edit-activity"].exists)
        XCTAssertFalse(app.buttons["delete-activity"].exists)
        XCTAssertFalse(app.buttons["activate-activity"].exists)
        find("activity-show-map", in: app).tap()
        XCTAssertEqual(app.staticTexts["map-selected-activity"].label, "Kembali ke bus")
    }
    @MainActor func testCalendarNativeEditorCanBeCancelledWithoutExportReceipt() {
        let app = mapDemo(); find("open-itinerary", in: app).tap()
        find("activity-row-00000000-0000-0000-0000-000000000501", in: app).tap()
        find("export-activity-calendar", in: app).tap()
        // This is Apple's real editor, not a fake in-app export confirmation.
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 8))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Native EventKit editor v5"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["calendar-export-status"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["calendar-export-status"].label.contains("dibatalkan"))
        XCTAssertTrue(app.buttons["export-activity-calendar"].label.contains("Tambahkan ke Calendar"))
    }

    @MainActor func testDynamicRouteStartsOnSelectedPersonAndStopsWithoutAttendanceChanges() {
        let app = mapDemo()
        find("open-location", in: app).tap()
        find("map-list", in: app).tap(); app.buttons["map-person-P01"].tap()
        find("map-start-routing", in: app).tap()
        XCTAssertTrue(app.staticTexts["map-routing-destination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map-routing-destination"].label.contains("Ayu"))
        XCTAssertTrue(app.staticTexts["map-routing-status"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Group dynamic routing"; shot.lifetime = .keepAlways; add(shot)
        find("map-stop-routing", in: app).tap()
        XCTAssertFalse(app.staticTexts["map-routing-destination"].exists)
        app.navigationBars.buttons["Selesai"].tap()
        XCTAssertTrue(find("counts", in: app).label.contains("V 2"))
    }
    @MainActor func testParticipantCanRouteToLeaderButNotToSelf() {
        let app = mapDemo(); app.tabBars.buttons["Peserta"].tap()
        find("open-participant-map", in: app).tap()
        find("map-list", in: app).tap(); app.buttons["map-person-YOU"].tap()
        XCTAssertFalse(app.buttons["map-start-routing"].exists)
        find("map-list", in: app).tap(); app.buttons["map-person-TL"].tap()
        find("map-start-routing", in: app).tap()
        XCTAssertTrue(app.staticTexts["map-routing-destination"].waitForExistence(timeout: 5))
        find("map-stop-routing", in: app).tap()
        XCTAssertFalse(app.staticTexts["map-routing-destination"].exists)
    }
    @MainActor func testDDSLabIsAvailableInsideMergedAppAndDismisses() {
        let app = launch(); app.tabBars.buttons["Lab"].tap()
        find("open-routing-lab", in: app).tap()
        XCTAssertTrue(app.buttons["Hitung rute"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Detail eksperimen"].exists)
        app.navigationBars.buttons["Selesai"].tap()
        XCTAssertTrue(app.buttons["open-routing-lab"].waitForExistence(timeout: 5))
    }

    @MainActor func testMergedDDSLiveStagesRemainSelectedWithoutStartingGPS() {
        let app = launch(); app.tabBars.buttons["Lab"].tap()
        find("open-routing-lab", in: app).tap()
        find("dds-stage-picker", in: app).tap()
        app.buttons["3 · GPS nyata"].tap()
        XCTAssertTrue(app.buttons["Mulai sesi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["GPS belum dimulai"].exists)
        find("dds-stage-picker", in: app).tap()
        app.buttons["5 · Background"].tap()
        XCTAssertTrue(app.buttons["Mulai sesi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["GPS belum dimulai"].exists)
        app.navigationBars.buttons["Selesai"].tap()
        XCTAssertTrue(app.buttons["open-routing-lab"].waitForExistence(timeout: 5))
    }

}
