//
//  SetupPDFContentTests.swift
//  Skema Tests
//
//  What goes into the shared A4 PDF (Sketch R15q, R15q·2).
//

import CoreGraphics
import Foundation
import Testing
@testable import Final_Challenge_App

@MainActor
@Suite("Setup PDF content")
struct SetupPDFContentTests {
    func makeSetup() -> Setup {
        let setup = Setup(setupName: "Skincare / soft daylight", client: "Aesop", project: "November catalog",
                          notes: "Flag the key light.", subjectHeight: "0.9")
        setup.createdAt = Date(timeIntervalSince1970: 1_793_577_600) // 2 Nov 2026
        setup.nodes.append(contentsOf: [
            Equipment(category: .camera, label: "C1", name: "Fujifilm GFX 50R", role: "Main camera", lens: "GF 63mm f/2.8",
                      iso: "100", aperture: "11", shutterSpeed: "1/125", whiteBalance: "5600", height: "1.4", tilt: "-10",
                      distance: "1.75"),
            Equipment(category: .accessory, label: "B1", name: "White foam board", role: "Bounce", distance: "1.28"),
            Equipment(category: .light, label: "L2", name: "Profoto D2 500", role: "Fill light", power: "5.5", colorTemp: "5600",
                      height: "1.45", tilt: "20", horizontalAim: "245", distance: "1.23", accessories: "60 × 90 cm softbox"),
            Equipment(category: .light, label: "L1", name: "Profoto D2 500", role: "Key light", power: "7.0", colorTemp: "5600",
                      height: "1.8", tilt: "35", horizontalAim: "135", distance: "1.35", accessories: "90 cm octabox")
        ])
        return setup
    }

    @Test("Header: name, client · project, saved date, notes")
    func header() {
        let content = SetupPDFContent(setup: makeSetup())

        #expect(content.title == "Skincare / soft daylight")
        #expect(content.subtitle == "Aesop · November catalog")
        #expect(content.savedLine == "Saved 2 Nov 2026")
        #expect(content.notes == "Flag the key light.")
    }

    @Test("Rows go lights, cameras, accessories by label, then the subject")
    func rowOrder() {
        let content = SetupPDFContent(setup: makeSetup())

        #expect(content.rows.map(\.id) == ["L1", "L2", "C1", "B1", "S"])
    }

    @Test("A light row shows accessories, distance, height · tilt · aim and power · colour temperature")
    func lightRow() {
        let row = SetupPDFContent(setup: makeSetup()).rows[0]

        #expect(row.name == "Profoto D2 500")
        #expect(row.role == "Key light")
        #expect(row.accessories == "90 cm octabox")
        #expect(row.distance == "1.35 m")
        #expect(row.placement == "1.8 m · 35° · 135°")
        #expect(row.settings == "7.0 · 5600 K")
    }

    @Test("A camera row shows its lens with the role and ISO · aperture · shutter · white balance")
    func cameraRow() {
        let row = SetupPDFContent(setup: makeSetup()).rows[2]

        #expect(row.role == "Main camera · GF 63mm f/2.8")
        #expect(row.placement == "1.4 m · -10° · —")
        #expect(row.settings == "ISO 100 · f/11 · 1/125 · 5600 K")
        #expect(row.accessories == "—")
    }

    @Test("Missing values show a dash")
    func blanks() {
        let rows = SetupPDFContent(setup: makeSetup()).rows

        #expect(rows[3].placement == "—")
        #expect(rows[3].settings == "—")
        #expect(rows[4] == SetupPDFContent.Row(id: "S", name: "Subject", role: "", accessories: "—",
                                               distance: "—", placement: "0.9 m", settings: "—"))
    }

    @Test("No subject row when the subject height is blank")
    func noSubjectRow() {
        let setup = makeSetup()
        setup.subjectHeight = " "

        #expect(SetupPDFContent(setup: setup).rows.map(\.id).contains("S") == false)
    }

    @Test("Summary counts lights, accessories and cameras", arguments: [
        (2, 1, 1, "2 lights · 1 accessory · 1 camera"),
        (1, 0, 2, "1 light · 2 cameras"),
        (0, 3, 0, "3 accessories"),
        (0, 0, 0, "No equipment")
    ])
    func summary(lights: Int, accessories: Int, cameras: Int, expected: String) {
        let setup = Setup(setupName: "Count")
        for index in 0..<lights { setup.nodes.append(Equipment(category: .light, label: "L\(index)")) }
        for index in 0..<accessories { setup.nodes.append(Equipment(category: .accessory, label: "A\(index)")) }
        for index in 0..<cameras { setup.nodes.append(Equipment(category: .camera, label: "C\(index)")) }

        #expect(SetupPDFContent(setup: setup).summary == expected)
    }

    @Test("File name is safe for Files and never blank", arguments: [
        ("Skincare / soft daylight", "Skincare - soft daylight.pdf"),
        ("Watch: rim light", "Watch- rim light.pdf"),
        ("   ", "Untitled Setup.pdf")
    ])
    func fileName(name: String, expected: String) {
        #expect(SetupPDFContent.fileName(for: name) == expected)
    }

    @Test("Sketch's 9 rows and 4 photos fit on one details page")
    func sketchFitsOnePage() {
        let pages = SetupPDFContent.detailPages(rowCount: 9, photoCount: 4)

        #expect(pages.count == 1)
        #expect(pages[0].rows == 0..<9)
        #expect(pages[0].photos == 0..<4)
    }

    @Test("Long lists spill onto more pages, every row and photo exactly once and in order",
          arguments: [(40, 0), (3, 13), (25, 9), (0, 0)])
    func pagination(rowCount: Int, photoCount: Int) {
        let pages = SetupPDFContent.detailPages(rowCount: rowCount, photoCount: photoCount)

        #expect(!pages.isEmpty)
        #expect(pages.flatMap { Array($0.rows) } == Array(0..<rowCount))
        #expect(pages.flatMap { Array($0.photos) } == Array(0..<photoCount))
        if rowCount > 20 || photoCount > 8 {
            #expect(pages.count > 1)
        }
    }

    @Test("The diagram zooms out to fit the box, never in past 1×")
    func diagramZoom() {
        let box = CGSize(width: 515, height: 380)

        #expect(SetupPDFContent.diagramZoom(for: [], in: box) == 1)
        #expect(SetupPDFContent.diagramZoom(for: [CGPoint(x: 50, y: 40)], in: box) == 1)
        // The lowest item's label must stay inside the box (C1 was clipped at y 200).
        let camera = SetupPDFContent.diagramZoom(for: [CGPoint(x: 0, y: 200)], in: box)
        #expect((200 + SetupPDFContent.diagramReachY) * camera <= box.height / 2 + 0.5)
        let far = SetupPDFContent.diagramZoom(for: [CGPoint(x: -400, y: 0), CGPoint(x: 0, y: 500)], in: box)
        #expect(far < 1)
        #expect(far > 0.3)
        #expect((500 + SetupPDFContent.diagramReachY) * far <= box.height / 2 + 0.5)
        #expect((400 + SetupPDFContent.diagramReachX) * far <= box.width / 2 + 0.5)
        #expect(SetupPDFContent.diagramZoom(for: [CGPoint(x: 0, y: 99_999)], in: box) == 0.3)
    }
}
