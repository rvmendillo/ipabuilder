import XCTest
@testable import ReyForgeCore

final class DropPlannerTests: XCTestCase {
    var project = Project(name: "Drop")
    var screen: Screen!
    var frames: [String: RFRect] = [:]

    override func setUp() {
        project = Project(name: "Drop")
        let a = Node(id: "A", type: .text, props: ["text": "A"])
        let b = Node(id: "B", type: .text, props: ["text": "B"])
        let c = Node(id: "C", type: .text, props: ["text": "C"])
        let h = Node(id: "H", type: .hstack, children: [b, c])
        let d = Node(id: "D", type: .text, props: ["text": "D"])
        let k = Node(id: "K", type: .card, children: [d])
        let e = Node(id: "E", type: .shape, style: Style(offsetX: 10, offsetY: 10))
        let z = Node(id: "Z", type: .zstack, children: [e])
        var root = Node.screenRoot()
        root.id = "R"
        root.children = [a, h, k, z]
        let s = Screen(id: "S", name: "Home", root: root)
        project.screens = [s]
        screen = s
        frames = [
            "R": RFRect(x: 0, y: 0, width: 390, height: 800),
            "A": RFRect(x: 16, y: 16, width: 358, height: 30),
            "H": RFRect(x: 16, y: 60, width: 358, height: 100),
            "B": RFRect(x: 16, y: 60, width: 170, height: 100),
            "C": RFRect(x: 204, y: 60, width: 170, height: 100),
            "K": RFRect(x: 16, y: 180, width: 358, height: 120),
            "D": RFRect(x: 32, y: 196, width: 326, height: 40),
            "Z": RFRect(x: 16, y: 320, width: 358, height: 200),
            "E": RFRect(x: 26, y: 330, width: 60, height: 60),
        ]
    }

    func target(_ x: Double, _ y: Double, moving: String? = nil, type: ComponentType = .text) -> DropTarget? {
        DropPlanner.target(in: screen, frames: frames, point: (x, y), dragging: moving, draggedType: type)
    }

    func testBeforeAndAfterLeafInVerticalStack() {
        let after = target(100, 40)!
        XCTAssertEqual(after.containerID, "R"); XCTAssertEqual(after.index, 1); XCTAssertEqual(after.placement, .after)
        let before = target(100, 20)!
        XCTAssertEqual(before.containerID, "R"); XCTAssertEqual(before.index, 0); XCTAssertEqual(before.placement, .before)
        XCTAssertEqual(before.indicator.height, 3)
    }

    func testHorizontalStackUsesXAxis() {
        let t = target(150, 110)!
        XCTAssertEqual(t.containerID, "H"); XCTAssertEqual(t.index, 1); XCTAssertEqual(t.placement, .after)
        XCTAssertEqual(t.indicator.width, 3, "vertical insertion line for horizontal stacks")
        let t2 = target(220, 110)!
        XCTAssertEqual(t2.containerID, "H"); XCTAssertEqual(t2.index, 1); XCTAssertEqual(t2.placement, .before)
    }

    func testInsideContainerAndNearEdge() {
        let inside = target(100, 270)!
        XCTAssertEqual(inside.containerID, "K"); XCTAssertEqual(inside.index, 1); XCTAssertEqual(inside.placement, .inside)
        let edge = target(100, 183)!
        XCTAssertEqual(edge.containerID, "R"); XCTAssertEqual(edge.index, 2); XCTAssertEqual(edge.placement, .before)
    }

    func testMovingExistingNodeComputesOriginalIndices() {
        // Move A after the card (bottom edge of K).
        let t = target(100, 298, moving: "A")!
        XCTAssertEqual(t.containerID, "R"); XCTAssertEqual(t.placement, .after)
        XCTAssertTrue(project.applyDrop(moving: "A", to: t))
        XCTAssertEqual(project.screens[0].root.children.map(\.id), ["H", "K", "A", "Z"])

        // Move A into the card, after D.
        setUp()
        let t2 = target(100, 270, moving: "A")!
        XCTAssertEqual(t2.containerID, "K")
        XCTAssertTrue(project.applyDrop(moving: "A", to: t2))
        XCTAssertEqual(project.node(id: "K")?.children.map(\.id), ["D", "A"])
        XCTAssertEqual(project.screens[0].root.children.map(\.id), ["H", "K", "Z"])
    }

    func testDroppingOnItsOwnSlotIsANoOp() {
        let t = target(100, 20, moving: "A")! // before H region? A is excluded; point is in root above H
        XCTAssertEqual(t.containerID, "R")
        XCTAssertFalse(project.applyDrop(moving: "A", to: t), "dropping where it already is changes nothing")
    }

    func testFreeLayoutDropSetsOffsets() {
        let t = target(100, 400, moving: "A")!
        XCTAssertEqual(t.containerID, "Z")
        XCTAssertEqual(t.freeOffset?.x, 84); XCTAssertEqual(t.freeOffset?.y, 80)
        XCTAssertTrue(project.applyDrop(moving: "A", to: t))
        let a = project.node(id: "A")!
        XCTAssertEqual(project.parent(of: "A")?.id, "Z")
        XCTAssertEqual(a.style.offsetX, 84); XCTAssertEqual(a.style.offsetY, 80)
        // Moving the existing free child only updates its offsets.
        let t2 = target(300, 500, moving: "E")!
        XCTAssertTrue(project.applyDrop(moving: "E", to: t2))
        XCTAssertEqual(project.node(id: "E")?.style.offsetX, 284)
        XCTAssertEqual(project.node(id: "Z")?.children.count, 2)
        // Leaving the free layout clears offsets.
        let t3 = target(100, 40, moving: "A")!
        XCTAssertTrue(project.applyDrop(moving: "A", to: t3))
        XCTAssertNil(project.node(id: "A")?.style.offsetX)
    }

    func testOutsideAppendsToRoot() {
        let t = target(100, 900)!
        XCTAssertEqual(t.containerID, "R"); XCTAssertEqual(t.index, 4)
        let new = ComponentRegistry.spec(for: .button).makeNode()
        let id = project.applyDrop(inserting: new, to: t)
        XCTAssertEqual(project.screens[0].root.children.last?.id, id)
    }

    func testCannotDropContainerIntoItself() {
        let t = target(100, 110, moving: "H", type: .hstack)!
        XCTAssertNotEqual(t.containerID, "H")
    }

    func testMenuOnlyAcceptsButtons() {
        var menu = ComponentRegistry.spec(for: .menu).makeNode()
        menu.id = "M"
        project.screens[0].root.children.append(menu)
        screen = project.screens[0]
        frames["M"] = RFRect(x: 16, y: 540, width: 200, height: 120)
        let t = target(100, 600, type: .image)!
        XCTAssertEqual(t.containerID, "R", "an image cannot go inside a menu")
        let t2 = target(100, 600, type: .button)!
        XCTAssertEqual(t2.containerID, "M")
    }
}
