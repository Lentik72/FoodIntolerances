//
//  FirstRunRootGatingUITests.swift
//  Food IntolerancesUITests
//
//  Root-gating test for the first-run flow (Task 11 follow-up).
//
//  What this test observes: with the first-run override active, the app's root
//  mounts the FirstRunFlowView branch and NOT the HealthOSRootView shell. That
//  is all it observes directly. It has no instrumentation for network traffic
//  or emit scheduling — the guarantee that the four launch side effects
//  (startObserving, initial emit, scene-active emit, location-recovery emit)
//  do not run during onboarding comes from this test PLUS the reviewed
//  modifier placement in FoodIntolerancesApp.swift, where those side effects
//  hang on HealthOSRootView() inside the else-branch rather than on the Group.
//  If the shell is absent, its branch-scoped modifiers never attach.
//
//  It also covers the injection-ordering mutant: the flow view mounts inside
//  the environmentObject chain, so a first-run view hoisted above the
//  injections would crash on first @EnvironmentObject access — this launch
//  would not survive to the first assertion.
//

import XCTest

final class FirstRunRootGatingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstRunGatesOutShellAndDefersLocationPrompt() throws {
        let app = XCUIApplication()
        // -key value form lands in NSArgumentDomain, so UserDefaults.standard
        // picks it up transiently. FirstRunKeys.forceShow == "hg.firstRun.forceShow"
        // (Models/FirstRunState.swift); the resolver honours it under #if DEBUG,
        // and UI tests run a Debug build. Forces .flow(.fresh) even on a
        // simulator that has already completed onboarding.
        app.launchArguments += ["-hg.firstRun.forceShow", "YES"]
        app.launch()

        // Settle on whichever branch mounted before asserting absence, so the
        // absence checks below cannot pass trivially against a blank first
        // frame. "Continue" is the flow's distinguishing control, "Capture"
        // the shell's — both are SwiftUI Buttons, so one buttons query covers
        // both branches.
        let branchMarker = app.buttons.matching(
            NSPredicate(format: "label == 'Continue' OR label == 'Capture'")
        ).firstMatch
        XCTAssertTrue(branchMarker.waitForExistence(timeout: 15),
                      "Neither root branch rendered a distinguishing control after launch")

        // 2. Shell-only controls must be absent. HealthOSTabBar renders one
        // SwiftUI Button per tab with .accessibilityLabel(tab.label) plus the
        // centre "Capture" button (Views/HealthOS/Shell/HealthOSTabBar.swift),
        // so these resolve in app.buttons — the same element type queried
        // above. Asserted BEFORE the flow-presence check so that, with
        // continueAfterFailure = false, a wrongly mounted shell fails HERE
        // rather than only on a missing Continue button.
        XCTAssertFalse(app.buttons["Capture"].exists,
                       "Shell capture button is on screen during first run — root gating is broken")
        XCTAssertFalse(app.buttons["Home"].exists,
                       "Shell 'Home' tab is on screen during first run — root gating is broken")
        XCTAssertFalse(app.buttons["Timeline"].exists,
                       "Shell 'Timeline' tab is on screen during first run — root gating is broken")
        XCTAssertFalse(app.buttons["Insights"].exists,
                       "Shell 'Insights' tab is on screen during first run — root gating is broken")
        XCTAssertFalse(app.buttons["Health"].exists,
                       "Shell 'Health' tab is on screen during first run — root gating is broken")

        // 1. The first-run flow is on screen. FirstRunPromiseView is still
        // Task 11's one-button stub (Button("Continue")).
        // TODO(Task 12): tighten this to the real promise headline once the
        // real promise screen lands.
        XCTAssertTrue(app.buttons["Continue"].exists,
                      "First-run promise screen is not on screen at launch")

        // 3. No system location dialog before the user reaches the Location
        // step. The system permission alert lives in SpringBoard's element
        // tree, not the app's. The failure mode is a dialog appearing a moment
        // after launch, so give it a settle window: waitForExistence returning
        // false after 3s is the PASS condition here.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 3),
                       "A system alert (e.g. location permission) appeared during the first-run promise screen")
        XCTAssertFalse(app.alerts.firstMatch.exists,
                       "An in-app alert appeared during the first-run promise screen")
    }
}
