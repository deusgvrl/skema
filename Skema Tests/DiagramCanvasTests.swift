import Testing
import CoreGraphics
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

    @Test("A name that would touch the item below it moves above; a name with room stays below")
    func nameNudged() {
        let points = [CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 145), CGPoint(x: 400, y: 400)]

        let sides = PDFDiagramLayout.nameSides(points: points, names: names(3), subject: CGPoint(x: 250, y: 250))

        #expect(sides == [.above, .below, .below])
    }
}
