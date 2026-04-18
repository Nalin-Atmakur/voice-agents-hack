//
// TacNetUITests.swift
//
// Automated XCUITest smoke walkthrough of every reachable non-BLE screen in the
// TacNet iOS app. Drives the app on the iPhone 17 Simulator via launch
// arguments that bypass the 6.7 GB model download gate and routes to
// synthetic hosts for screens that require real BLE (e.g. PIN entry).
//
// Mapped to validation contract assertions VAL-UI-001 through VAL-UI-013.
//

import XCTest

final class TacNetUISmokeTests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func makeApp(
        route: String? = nil,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["--ui-test-skip-download"]
        if let route {
            args.append("--ui-test-route=\(route)")
        }
        args.append(contentsOf: additionalArguments)
        app.launchArguments = args
        return app
    }

    private func saveScreenshot(_ app: XCUIApplication, named name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForExistence(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        message: String = ""
    ) {
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(
            exists,
            "\(message) Element \(element) was not found within \(timeout)s"
        )
    }

    /// Resolves an accessibility identifier irrespective of XCUIElement type (Other,
    /// ScrollView, StaticText, etc.) which depends on how SwiftUI composes the view.
    private func anyElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    // MARK: - VAL-UI-001 · App launch, no crash, UI visible within 5s

    func testAppLaunchesAndRemainsAliveWithVisibleUI() {
        let app = makeApp()
        app.launch()

        let welcomeRoot = app.otherElements["tacnet.welcome.root"]
        waitForExistence(welcomeRoot, timeout: 8, message: "Welcome did not render after launch.")
        saveScreenshot(app, named: "launch-welcome")

        // App should remain alive for at least 15 seconds with UI still visible.
        let totalWaitSeconds: TimeInterval = 15
        let startDate = Date()
        while Date().timeIntervalSince(startDate) < totalWaitSeconds {
            XCTAssertEqual(
                app.state,
                .runningForeground,
                "App left foreground state before \(totalWaitSeconds)s"
            )
            _ = XCUIApplication().wait(for: .runningForeground, timeout: 1)
        }
        saveScreenshot(app, named: "launch-after-15s")
    }

    // MARK: - VAL-UI-002 · Initial screen renders appropriately

    func testInitialScreenRendersWithoutBlankState() {
        let app = makeApp()
        app.launch()

        let welcomeRoot = app.otherElements["tacnet.welcome.root"]
        waitForExistence(welcomeRoot, timeout: 8)

        // Welcome screen must expose both affordances once the download gate is bypassed.
        XCTAssertTrue(app.buttons["tacnet.welcome.createNetworkButton"].exists)
        XCTAssertTrue(app.buttons["tacnet.welcome.joinNetworkButton"].exists)
        saveScreenshot(app, named: "initial-welcome")
    }

    // MARK: - VAL-UI-003 · Welcome navigates to Create and Join

    func testWelcomeNavigatesToCreateAndJoin() {
        let app = makeApp()
        app.launch()
        let createButton = app.buttons["tacnet.welcome.createNetworkButton"]
        let joinButton = app.buttons["tacnet.welcome.joinNetworkButton"]
        waitForExistence(createButton)

        // Tap Create Network — should navigate to Tree Builder.
        createButton.tap()
        let treeBuilderRoot = app.scrollViews["tacnet.treeBuilder.root"]
            .firstMatch.exists ? app.scrollViews["tacnet.treeBuilder.root"] : app.otherElements["tacnet.treeBuilder.root"]
        // Fall back to existence check via any Tree Builder control we know is present.
        let addChildButton = app.buttons["tacnet.treeBuilder.addChildButton"]
        waitForExistence(addChildButton, timeout: 6, message: "Tree Builder did not render.")
        saveScreenshot(app, named: "create-network-treebuilder")

        // Back to welcome.
        let backButton = app.buttons["tacnet.treeBuilder.backButton"]
        if backButton.exists {
            backButton.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        waitForExistence(joinButton, timeout: 6, message: "Welcome did not re-appear after Tree Builder back.")

        // Tap Join Network — should navigate to Network Scan.
        joinButton.tap()
        let scanRoot = app.otherElements["tacnet.scan.root"]
        waitForExistence(scanRoot, timeout: 6, message: "Network Scan did not render.")
        saveScreenshot(app, named: "join-network-scan")
    }

    // MARK: - VAL-UI-004 · Tree Builder add/rename/remove flow

    func testTreeBuilderAddRenameRemoveCycle() {
        let app = makeApp()
        app.launch()
        app.buttons["tacnet.welcome.createNetworkButton"].tap()

        let addChildButton = app.buttons["tacnet.treeBuilder.addChildButton"]
        waitForExistence(addChildButton, timeout: 6)
        saveScreenshot(app, named: "treebuilder-empty")

        // Add a child node.
        let newChildField = app.textFields["tacnet.treeBuilder.newChildField"]
        waitForExistence(newChildField)
        newChildField.tap()
        newChildField.typeText("Alpha")
        addChildButton.tap()
        saveScreenshot(app, named: "treebuilder-after-add")
        XCTAssertTrue(
            app.staticTexts["Alpha"].waitForExistence(timeout: 4),
            "Newly added child 'Alpha' did not appear in the tree."
        )

        // Rename the selected node (the just-added child is auto-selected).
        let renameField = app.textFields["tacnet.treeBuilder.renameField"]
        waitForExistence(renameField)
        renameField.tap()
        // Clear existing text by selecting all then typing.
        if let existing = renameField.value as? String, !existing.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            renameField.typeText(deleteString)
        }
        renameField.typeText("Bravo")
        app.buttons["tacnet.treeBuilder.renameButton"].tap()
        saveScreenshot(app, named: "treebuilder-after-rename")
        XCTAssertTrue(
            app.staticTexts["Bravo"].waitForExistence(timeout: 4),
            "Renamed node 'Bravo' did not appear in the tree."
        )

        // Remove the node.
        app.buttons["tacnet.treeBuilder.removeButton"].tap()
        saveScreenshot(app, named: "treebuilder-after-remove")
        // After removal the 'Bravo' label should be gone.
        let bravoGone = !app.staticTexts["Bravo"].waitForExistence(timeout: 2)
        XCTAssertTrue(bravoGone, "Removed node 'Bravo' is still visible in the tree.")
    }

    // MARK: - VAL-UI-005 · Network Scan empty state

    func testNetworkScanRendersEmptyStateWithoutBLE() {
        let app = makeApp()
        app.launch()
        app.buttons["tacnet.welcome.joinNetworkButton"].tap()

        let scanRoot = app.otherElements["tacnet.scan.root"]
        waitForExistence(scanRoot, timeout: 6)
        saveScreenshot(app, named: "scan-empty")

        // Rescan and back should not crash.
        let rescan = app.buttons["tacnet.scan.rescanButton"]
        waitForExistence(rescan)
        rescan.tap()
        saveScreenshot(app, named: "scan-after-rescan")

        app.buttons["tacnet.scan.backButton"].tap()
        waitForExistence(
            app.buttons["tacnet.welcome.createNetworkButton"],
            timeout: 4,
            message: "Did not return to Welcome after Back from Scan."
        )
    }

    // MARK: - VAL-UI-006 · PIN entry renders and accepts input

    func testPinEntryRendersAndAcceptsDigits() {
        let app = makeApp(route: "pin-entry")
        app.launch()

        let pinField = app.secureTextFields["tacnet.pin.field"]
        waitForExistence(pinField, timeout: 6, message: "Pin entry field did not render.")
        saveScreenshot(app, named: "pin-entry")

        pinField.tap()
        pinField.typeText("1234")

        let submit = app.buttons["tacnet.pin.submitButton"]
        waitForExistence(submit)
        submit.tap()

        // Our UI-test host surfaces the submitted value for verification.
        let submitted = app.staticTexts["tacnet.pin.submittedValue"]
        waitForExistence(submitted, timeout: 4, message: "Pin submission did not reach host observer.")
        saveScreenshot(app, named: "pin-entry-submitted")
    }

    // MARK: - VAL-UI-007 · Role Selection with seeded tree

    func testRoleSelectionRendersSeededTreeAndClaimControl() {
        let app = launchAndPublishSeededNetwork()

        let roleRoot = app.otherElements["tacnet.roleSelection.root"]
        waitForExistence(roleRoot, timeout: 8, message: "Role Selection did not render.")
        saveScreenshot(app, named: "role-selection")

        // Seeded tree has a root + at least one claimable child (we added one).
        let alphaRow = app.staticTexts["Alpha"]
        XCTAssertTrue(
            alphaRow.waitForExistence(timeout: 4),
            "Role Selection does not show seeded 'Alpha' node."
        )

        // The Back button should always be present.
        XCTAssertTrue(app.buttons["tacnet.roleSelection.backButton"].exists)
    }

    // MARK: - VAL-UI-008 through VAL-UI-012 · Tabs render and switch without crash

    func testMainTreeDataFlowSettingsTabsRenderAndSwitch() {
        let app = launchAndPublishSeededNetwork()

        // Claim the seeded child node to reach the main tab shell. The row's
        // accessibility identifier is "tacnet.roleSelection.row.<nodeID>";
        // we locate it by the visible label we set (Alpha) inside any matching
        // button cell.
        let alphaStaticText = app.staticTexts["Alpha"]
        waitForExistence(alphaStaticText, timeout: 8)

        // Tap the enclosing button cell for reliability.
        let claimableCell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tacnet.roleSelection.row.")).element(matching: NSPredicate(format: "label CONTAINS %@", "Alpha"))
        if claimableCell.exists {
            claimableCell.tap()
        } else {
            alphaStaticText.tap()
        }
        saveScreenshot(app, named: "after-claim-tap")

        let tabBar = app.tabBars.firstMatch
        waitForExistence(tabBar, timeout: 12, message: "Tab bar did not appear after role claim.")

        // Main tab — PTT button interacts without crash.
        let mainTab = tabBar.buttons["Main"]
        waitForExistence(mainTab)
        mainTab.tap()
        let mainRoot = anyElement(app, identifier: "tacnet.main.root")
        waitForExistence(mainRoot, timeout: 6, message: "Main tab did not render.")
        saveScreenshot(app, named: "tab-main")

        // The PTT control is combined into a single element — look up by id.
        let pttControl = anyElement(app, identifier: "tacnet.main.pttControl")
        waitForExistence(pttControl, timeout: 6, message: "PTT control did not render on Main tab.")
        // Press (no crash expected even if mesh is disconnected — must NOT hang).
        pttControl.press(forDuration: 0.3)
        saveScreenshot(app, named: "tab-main-after-ptt")

        // Tree tab.
        let treeTab = tabBar.buttons["Tree View"]
        if treeTab.exists {
            treeTab.tap()
        }
        waitForExistence(anyElement(app, identifier: "tacnet.tree.root"), timeout: 4, message: "Tree tab did not render.")
        saveScreenshot(app, named: "tab-tree")

        // Data Flow tab.
        let dataFlowTab = tabBar.buttons["Data Flow"]
        if dataFlowTab.exists {
            dataFlowTab.tap()
        }
        waitForExistence(anyElement(app, identifier: "tacnet.dataflow.root"), timeout: 4, message: "Data Flow tab did not render.")
        XCTAssertTrue(app.staticTexts["INCOMING"].exists, "Data Flow tab missing INCOMING section header")
        XCTAssertTrue(app.staticTexts["PROCESSING"].exists, "Data Flow tab missing PROCESSING section header")
        XCTAssertTrue(app.staticTexts["OUTGOING"].exists, "Data Flow tab missing OUTGOING section header")
        saveScreenshot(app, named: "tab-dataflow")

        // Settings tab.
        let settingsTab = tabBar.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()
        }
        waitForExistence(anyElement(app, identifier: "tacnet.settings.root"), timeout: 4, message: "Settings tab did not render.")
        saveScreenshot(app, named: "tab-settings")

        // Cycle back through tabs in another order — no crash expected.
        mainTab.tap()
        waitForExistence(anyElement(app, identifier: "tacnet.main.root"), timeout: 4)
        if dataFlowTab.exists { dataFlowTab.tap() }
        waitForExistence(anyElement(app, identifier: "tacnet.dataflow.root"), timeout: 4)
        if treeTab.exists { treeTab.tap() }
        waitForExistence(anyElement(app, identifier: "tacnet.tree.root"), timeout: 4)
        if settingsTab.exists { settingsTab.tap() }
        waitForExistence(anyElement(app, identifier: "tacnet.settings.root"), timeout: 4)
        saveScreenshot(app, named: "tab-cycle-final")

        // App must still be running after the full walk.
        XCTAssertEqual(app.state, .runningForeground, "App is not running after full tab walkthrough.")
    }

    // MARK: - Helpers for seeded flow

    /// Launches the app, walks Welcome → Create Network → Tree Builder, adds one child,
    /// publishes the network, and returns the app handle at the Role Selection screen.
    private func launchAndPublishSeededNetwork() -> XCUIApplication {
        let app = makeApp()
        app.launch()

        app.buttons["tacnet.welcome.createNetworkButton"].tap()

        let addChildButton = app.buttons["tacnet.treeBuilder.addChildButton"]
        waitForExistence(addChildButton, timeout: 8)

        let newChildField = app.textFields["tacnet.treeBuilder.newChildField"]
        waitForExistence(newChildField)
        newChildField.tap()
        newChildField.typeText("Alpha")
        addChildButton.tap()

        let publishButton = app.buttons["tacnet.treeBuilder.publishButton"]
        waitForExistence(publishButton, timeout: 4)
        publishButton.tap()

        return app
    }
}
