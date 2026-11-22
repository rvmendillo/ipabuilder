import XCTest

final class SmokeUITests: XCTestCase {
    func testLaunch() {
        let app = XCUIApplication()
        app.launch()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "launch"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
