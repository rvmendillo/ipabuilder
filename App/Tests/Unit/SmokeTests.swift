import XCTest
import ReyForgeCore
@testable import ReyForge

final class SmokeTests: XCTestCase {
    func testTemplatesLoad() {
        XCTAssertFalse(Templates.all.isEmpty)
        XCTAssertNotNil(FixtureData.p12.first)
    }
}
