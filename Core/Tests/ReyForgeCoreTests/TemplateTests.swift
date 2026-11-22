import XCTest
@testable import ReyForgeCore

final class TemplateTests: XCTestCase {
    func testEveryTemplateBuildsCleanly() {
        XCTAssertGreaterThanOrEqual(Templates.all.count, 15)
        for t in Templates.all {
            let r = RFSCompiler.compile(t.script(), into: Project(name: t.name))
            XCTAssertTrue(r.warnings.isEmpty, "\(t.id) warnings: \(r.warnings)")
            let p = t.makeProject()
            XCTAssertEqual(p.templateID, t.id)
            XCTAssertTrue(BundleID.isValid(p.bundleID), "\(t.id) bundle id \(p.bundleID)")
            let issues = ProjectValidator.validate(p)
            XCTAssertTrue(issues.isEmpty, "\(t.id): \(issues)")
            XCTAssertFalse(p.screens.isEmpty)
            // Round-trips through JSON (what the IPA runtime loads).
            let back = try? Project.decode(try p.jsonData())
            XCTAssertEqual(back?.screens.count, p.screens.count, t.id)
        }
    }

    func testCatalogCoversNearlyAllComponents() {
        let p = Templates.template("catalog")!.makeProject()
        let used = Set(p.allNodes.map { $0.node.type })
        let missing = Set(ComponentType.allCases).subtracting(used)
        XCTAssertTrue(missing.isEmpty, "Catalog is missing: \(missing.map { $0.rawValue }.sorted())")
        XCTAssertEqual(p.navigation.tabs.count, 5)
        XCTAssertFalse(p.screen(named: "Controls")!.toolbar.isEmpty)
        // Every button variant and picker style is demonstrated.
        let variants = Set(p.allNodes.filter { $0.node.type == .button }.map { $0.node.string("variant") })
        XCTAssertTrue(variants.isSuperset(of: ["prominent", "bordered", "plain", "borderless", "glass", "capsule", "destructive"]), "\(variants)")
        let pickers = Set(p.allNodes.filter { $0.node.type == .picker }.map { $0.node.string("variant") })
        XCTAssertTrue(pickers.isSuperset(of: ["segmented", "menu", "wheel", "inline"]))
        let charts = Set(p.allNodes.filter { $0.node.type == .chart }.map { $0.node.string("kind") })
        XCTAssertEqual(charts, ["bar", "line", "area", "pie", "donut", "point"])
        let about = p.screen(named: "About")!
        XCTAssertFalse(about.root.flattened.contains { $0.string("text").contains("This is the About screen") }, "stub content replaced")
        let shapes = Set(p.allNodes.filter { $0.node.type == .shape }.map { $0.node.string("shape") })
        XCTAssertEqual(shapes, ["circle", "capsule", "roundedRectangle", "rectangle", "ellipse"])
    }

    func testTemplatesProduceDistinctIDs() {
        let a = Templates.template("finance")!.makeProject()
        let b = Templates.template("finance")!.makeProject(named: "My Money")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.screens[0].id, b.screens[0].id)
        XCTAssertEqual(b.brand.displayName, "My Money")
        XCTAssertEqual(b.bundleID, "com.reyforge.mymoney")
        XCTAssertEqual(a.initialScreen?.name, "Welcome", "onboarding first")
    }

    func testWidgetTemplate() {
        let p = Templates.template("widget")!.makeProject()
        XCTAssertTrue(p.widget.enabled)
        XCTAssertEqual(p.widget.family, .small)
        XCTAssertTrue(p.variable(named: "count")!.persist)
    }
}
