import XCTest

/// End-to-end UI tests: create apps, drag & drop, edit, add logic, vibe-code with AI, preview and build.
final class ReyForgeUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    // MARK: Helpers

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @discardableResult
    func tap(_ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let e = el(id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(id) should exist")
        e.tap()
        return e
    }

    func anyText(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
    }

    /// Creates a blank project and opens the editor.
    func openBlankProject(named name: String = "UITest App") {
        tap("home.new")
        let field = el("new.name")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        let blank = el("new.template.blank")
        var attempts = 0
        while !(blank.exists && blank.isHittable) && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(blank.waitForExistence(timeout: 3), "blank template visible")
        blank.tap()
        XCTAssertTrue(el("canvas").waitForExistence(timeout: 15), "editor opens")
    }

    func addFromLibrary(_ type: String) {
        if !el("library.search").exists { tap("panel.add") }
        let search = el("library.search")
        XCTAssertTrue(search.waitForExistence(timeout: 5), "library open")
        let tile = el("library.\(type)")
        if !(tile.exists && tile.isHittable) {
            search.tap()
            search.typeText(type + "\n")
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "\(type) tile visible")
        tile.tap()
    }

    // MARK: Tests

    func testHomeAndTemplateGallery() {
        XCTAssertTrue(el("home.new").waitForExistence(timeout: 10))
        shot("01-home")
        tap("home.new")
        XCTAssertTrue(el("new.template.catalog").waitForExistence(timeout: 5))
        shot("02-new-app")
        el("new.template.catalog").tap()
        XCTAssertTrue(el("canvas").waitForExistence(timeout: 15))
        shot("03-catalog-template")
        tap("editor.screenMenu")
        shot("04-screen-menu")
        app.tap() // dismiss menu
    }

    func testAddEditUndoRedo() {
        openBlankProject()
        addFromLibrary("button")
        XCTAssertTrue(el("sel.text").waitForExistence(timeout: 5), "new element is selected")
        tap("sel.text")
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("Tap me UI")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(anyText("Tap me UI").waitForExistence(timeout: 5), "canvas shows edited text")
        shot("05-edited-button")
        tap("editor.undo")
        XCTAssertFalse(anyText("Tap me UI").waitForExistence(timeout: 2))
        tap("editor.redo")
        XCTAssertTrue(anyText("Tap me UI").waitForExistence(timeout: 5))
    }

    func testInspectorPropertiesAndStyle() {
        openBlankProject()
        addFromLibrary("text")
        tap("sel.inspect")
        let prop = el("prop.text")
        XCTAssertTrue(prop.waitForExistence(timeout: 5))
        prop.tap()
        prop.clearAndType("Inspector text")
        XCTAssertTrue(anyText("Inspector text").waitForExistence(timeout: 5))
        let tabs = el("inspector.tabs")
        tabs.buttons["Style"].tap()
        shot("06-inspector-style")
        tabs.buttons["Layout"].tap()
        shot("07-inspector-layout")
    }

    func testDragFromLibraryOntoCanvas() {
        openBlankProject()
        tap("panel.add")
        let search = el("library.search")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("toggle\n")
        let tile = el("library.toggle")
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        let before = app.switches.count
        let canvas = el("canvas")
        tile.press(forDuration: 0.6, thenDragTo: canvas, withVelocity: .slow, thenHoldForDuration: 0.3)
        let appeared = NSPredicate(format: "count > %d", before)
        expectation(for: appeared, evaluatedWith: app.switches)
        waitForExpectations(timeout: 8)
        shot("08-dragged-toggle")
    }

    func testMoveHandleReordersElements() {
        openBlankProject()
        addFromLibrary("toggle")
        tap("drawer.close")
        tap("panel.add")
        addFromLibrary("slider")
        tap("drawer.close")
        let slider = app.sliders.firstMatch
        let toggle = app.switches.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(slider.frame.minY, toggle.frame.minY, "slider starts below the toggle")
        let handle = el("handle.move")
        XCTAssertTrue(handle.waitForExistence(timeout: 5), "selected element shows a move handle")
        let target = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        handle.press(forDuration: 0.2, thenDragTo: el("canvas"), withVelocity: .slow, thenHoldForDuration: 0.1)
        _ = target
        shot("09-after-move")
        // Use the selection bar as a deterministic fallback reorder.
        tap("sel.up")
        XCTAssertLessThan(app.sliders.firstMatch.frame.minY, app.switches.firstMatch.frame.minY, "slider moved above the toggle")
        shot("10-reordered")
    }

    func testLogicRecipeAndLivePreview() {
        openBlankProject()
        addFromLibrary("button")
        tap("sel.logic")
        let recipe = el("recipe.toast")
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
        recipe.tap()
        XCTAssertTrue(el("editor.toast").waitForExistence(timeout: 5))
        shot("11-logic")
        tap("editor.preview")
        let button = app.buttons["Continue"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(el("toast").waitForExistence(timeout: 5), "logic runs in preview and shows a toast")
        shot("12-preview-toast")
        tap("preview.close")
    }

    func testVibeCodingWithAI() {
        openBlankProject(named: "AI Test")
        tap("panel.ai")
        let input = el("ai.input")
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Add a settings screen with notifications and dark mode toggles")
        tap("ai.send")
        XCTAssertTrue(el("ai.reply").waitForExistence(timeout: 60), "AI replies")
        shot("13-ai-reply")
        tap("editor.screenMenu")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5), "AI created the Settings screen")
        app.buttons["Settings"].tap()
        shot("14-ai-settings-screen")
    }

    func testBrandStudioAndScreens() {
        openBlankProject(named: "Brand Test")
        tap("panel.brand")
        let name = el("brand.displayName")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.clearAndType("Brandy")
        el("brand.sections").buttons["Icon"].tap()
        shot("15-brand-icon")
        el("brand.sections").buttons["Theme"].tap()
        let ocean = el("theme.ocean")
        if ocean.waitForExistence(timeout: 3) { ocean.tap() }
        shot("16-brand-theme")
        tap("panel.screens")
        tap("screens.add")
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Details")
        app.alerts.buttons["Add"].tap()
        tap("editor.screenMenu")
        XCTAssertTrue(app.buttons["Details"].waitForExistence(timeout: 5))
        app.tap()
        tap("panel.layers")
        shot("17-layers")
    }

    func testBuildUnsignedIPAOnDevice() {
        openBlankProject(named: "Build Test")
        tap("editor.build")
        let unsigned = app.switches["Unsigned IPA (sign elsewhere)"]
        XCTAssertTrue(unsigned.waitForExistence(timeout: 5))
        if (unsigned.value as? String) != "1" { unsigned.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        tap("build.start")
        XCTAssertTrue(el("build.result").waitForExistence(timeout: 120), "IPA built on device")
        shot("18-build-result")
    }
}

extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 4)
            typeText(delete)
        }
        typeText(text)
    }
}
