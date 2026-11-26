import Testing
import CoreGraphics
import Foundation
@testable import Skema_Photo

/// Where the PDF diagram draws the subject, each item and its name inside the PDF's box (26 Nov):
/// it fills the box, draws a far item just outside the others with a break mark, and moves a name that would touch.
@MainActor
@Suite("PDF diagram layout")
struct PDFDiagramLayoutTests {
    private let box = CGSize(width: 507, height: 520)
    private let pad = PDFDiagramLayout.padding

    private func names(_ count: Int) -> [String] { (1...count).map { "Light \($0)" } }

    /// The drawn subject and items, as one bounding box.
    private func bounds(_ layout: PDFDiagramLayout.Result) -> CGRect {
        let points = [layout.subject] + layout.points
        let across = points.map(\.x), down = points.map(\.y)
        return CGRect(x: across.min()!, y: down.min()!,
                      width: across.max()! - across.min()!, height: down.max()! - down.min()!)
    }

    @Test("A setup with everything on one side fills the box, not just half of it")
    func oneSidedFillsBox() {
        let positions = [CGPoint(x: 0, y: 260), CGPoint(x: -170, y: 120), CGPoint(x: 170, y: 130),
                         CGPoint(x: -90, y: 230)]

        let drawn = bounds(PDFDiagramLayout.make(positions: positions, names: names(4), in: box))

        let filled = max((drawn.width + 2 * pad) / box.width, (drawn.height + 2 * pad) / box.height)
        #expect(abs(filled - 1) < 0.01)
    }

    @Test("A close pair is spread at least 90 pt apart when the box allows")
    func closePairSpread() {
        let positions = [CGPoint(x: -30, y: -100), CGPoint(x: 30, y: -100), CGPoint(x: 0, y: 150)]

        let layout = PDFDiagramLayout.make(positions: positions, names: names(3), in: box)

        #expect(hypot(layout.points[0].x - layout.points[1].x, layout.points[0].y - layout.points[1].y) >= 90)
    }

    @Test("A far item is drawn just outside the others, in its own direction, with a break mark; the rest are not")
    func farItemBroken() {
        let positions = [CGPoint(x: 0, y: 250), CGPoint(x: -180, y: -120), CGPoint(x: -125, y: -160),
                         CGPoint(x: 200, y: -150), CGPoint(x: 0, y: -700)]

        let layout = PDFDiagramLayout.make(positions: positions, names: names(5), in: box)

        #expect(layout.isBroken == [false, false, false, false, true])
        let far = CGPoint(x: layout.points[4].x - layout.subject.x, y: layout.points[4].y - layout.subject.y)
        #expect(abs(far.x) < 0.5 && far.y < 0, "Same direction as the real item: straight up.")
        let nearest = (0..<4).map { index in
            hypot(layout.points[index].x - layout.subject.x, layout.points[index].y - layout.subject.y)
        }
        #expect(hypot(far.x, far.y) > nearest.max()!, "Still drawn farther than the others.")
        let drawn = bounds(layout)
        #expect(drawn.minX - pad >= -0.5 && drawn.minY - pad >= -0.5, "Nothing is cut off at the top or left.")
        #expect(drawn.maxX + pad <= box.width + 0.5 && drawn.maxY + pad <= box.height + 0.5, "Or the bottom or right.")
    }

    @Test("With no far item, nothing has a break mark")
    func nothingBroken() {
        let positions = [CGPoint(x: 0, y: 250), CGPoint(x: -180, y: -120), CGPoint(x: 200, y: -150)]

        let layout = PDFDiagramLayout.make(positions: positions, names: names(3), in: box)

        #expect(layout.isBroken == [false, false, false])
    }

    // MARK: Nothing overlaps, accessories included (27 Nov)

    /// One item of a test setup: its kind, name and position (diagram points from the subject).
    @MainActor
    private struct Spec {
        let category: EquipmentCategory
        var accessoryType: AccessoryType = .reflector
        let name: String
        let posX: CGFloat
        let posY: CGFloat

        static func light(_ name: String, _ posX: CGFloat, _ posY: CGFloat) -> Spec {
            Spec(category: .light, name: name, posX: posX, posY: posY)
        }

        static func camera(_ posX: CGFloat, _ posY: CGFloat) -> Spec {
            Spec(category: .camera, name: "Camera", posX: posX, posY: posY)
        }

        static func accessory(_ type: AccessoryType, _ posX: CGFloat, _ posY: CGFloat) -> Spec {
            Spec(category: .accessory, accessoryType: type, name: type.title, posX: posX, posY: posY)
        }
    }

    /// Items as the PDF draws them: each icon's real shape, turned to face the subject, and its distance label.
    private func items(_ specs: [Spec]) -> [PDFDiagramLayout.Item] {
        specs.map { spec in
            let item = Equipment(category: spec.category, accessoryType: spec.accessoryType, name: spec.name,
                                 position: CGPoint(x: spec.posX, y: spec.posY))
            item.pointToSubject()
            let footprint = PDFDiagramLayout.footprint(of: spec.category, accessoryType: spec.accessoryType)
            return PDFDiagramLayout.Item(position: item.position, name: spec.name, footprint: footprint,
                                         rotation: item.rotationAngle,
                                         distanceText: String(format: "%.2f m", hypot(spec.posX, spec.posY) / 100))
        }
    }

    /// The render that showed the overlaps: a diffuser in front of the key light, a reflector by the subject,
    /// a backdrop behind it.
    private var studio: [Spec] {
        [.camera(0, 250), .light("Key light", -180, -120), .accessory(.diffuser, -120, -80),
         .light("Fill light", 200, -100), .accessory(.reflector, 70, 40), .accessory(.backdrop, 0, -150),
         .light("Rim light", 120, -220)]
    }

    private func subjectRect(_ layout: PDFDiagramLayout.Result) -> CGRect {
        let size = PDFDiagramLayout.subjectSize
        return CGRect(x: layout.subject.x - size.width / 2, y: layout.subject.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Index pairs that overlap, for a readable failure.
    private func touching(_ rects: [CGRect]) -> [[Int]] {
        rects.indices.flatMap { first in
            rects.indices.filter { $0 > first && rects[first].intersects(rects[$0]) }.map { [first, $0] }
        }
    }

    @Test("A diffuser turned 90° takes 7 pt across and 46 pt along")
    func turnedFootprint() {
        let size = PDFDiagramLayout.rotatedSize(PDFDiagramLayout.footprint(of: .accessory, accessoryType: .diffuser),
                                                degrees: 90)

        #expect(abs(size.width - 7) < 0.01 && abs(size.height - 46) < 0.01)
    }

    @Test("No icon touches another icon or the subject, in the studio and with a diffuser 0.3 m in front of a light")
    func iconsApart() {
        let diffuserInFront: [Spec] = [.light("Key light", 0, -250), .accessory(.diffuser, 0, -220), .camera(0, 250)]
        for specs in [studio, diffuserInFront] {
            let layout = PDFDiagramLayout.make(items: items(specs), in: box)

            #expect(touching(layout.iconRects).isEmpty)
            #expect(!layout.iconRects.contains { $0.intersects(subjectRect(layout)) })
        }
    }

    @Test("No distance label touches another label, an icon, a name or the subject")
    func distancesClear() throws {
        let layout = PDFDiagramLayout.make(items: items(studio), in: box)
        let labels = layout.distanceRects.compactMap { $0 }

        #expect(labels.count == studio.count)
        #expect(touching(labels).isEmpty)
        for label in labels {
            let others = layout.iconRects + layout.nameRects + [subjectRect(layout)]
            #expect(!others.contains { $0.intersects(label) })
        }
    }

    @Test("A name goes on the side facing away from the subject")
    func nameOutward() {
        let positions = [CGPoint(x: 0, y: -200), CGPoint(x: 0, y: 200), CGPoint(x: 220, y: 0)]

        let layout = PDFDiagramLayout.make(positions: positions, names: names(3), in: box)

        #expect(layout.nameSides == [.above, .below, .right])
    }

    @Test("The backdrop's name crosses no line from the subject")
    func backdropNameClearOfLines() throws {
        let layout = PDFDiagramLayout.make(items: items(studio), in: box)
        let backdrop = try #require(studio.firstIndex { $0.name == "Backdrop" })

        #expect(!layout.points.contains { point in
            PDFDiagramLayout.segment(from: layout.subject, to: point, crosses: layout.nameRects[backdrop])
        })
    }

    @Test("A name moves off another item's line, even from its outward side")
    func nameClearOfAnotherLine() throws {
        // The rim light's line passes just above the backdrop, where its name would go.
        let specs: [Spec] = [.accessory(.backdrop, 0, -150), .light("Rim light", 40, -300), .camera(0, 250)]

        let layout = PDFDiagramLayout.make(items: items(specs), in: box)

        #expect(!layout.points.contains { point in
            PDFDiagramLayout.segment(from: layout.subject, to: point, crosses: layout.nameRects[0])
        })
    }

    @Test("Names and distance labels stay inside the box")
    func labelsInsideBox() {
        let oneSided: [Spec] = [.camera(0, 260), .light("Light 1", -170, 120), .light("Light 2", 170, 130),
                                .accessory(.reflector, -90, 230)]
        let bounds = CGRect(origin: .zero, size: box)
        for specs in [oneSided, studio] {
            let layout = PDFDiagramLayout.make(items: items(specs), in: box)

            #expect(layout.nameRects.allSatisfy { bounds.contains($0) })
            #expect(layout.distanceRects.compactMap { $0 }.allSatisfy { bounds.contains($0) })
        }
    }
}
