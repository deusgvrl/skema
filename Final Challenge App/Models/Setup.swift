import SwiftUI
import SwiftData
import Foundation

/// A saved lighting setup. Fields are added with A10-13.
@Model
final class Setup {
    @Attribute(.unique) var id: UUID
    var setupName: String
    var client: String
    var project: String
    var notes: String
    var subjectHeight: String = ""

    // Subject Orientation (Matching Equipment's horizontalAim / rotationAngle)
    var subjectHorizontalAim: String = "0"
    var subjectRotationAngle: Double = 0.0

    var firstSavedDate: Date?
    var deletedDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \Equipment.setup)
    var nodes: [Equipment] = []

    @Relationship(deleteRule: .cascade, inverse: \ReferenceImage.setup)
    var referenceImages: [ReferenceImage] = []

    init(
        id: UUID = UUID(),
        setupName: String = "",
        client: String = "",
        project: String = "",
        notes: String = "",
        subjectHeight: String = "",
        subjectHorizontalAim: String = "0",
        subjectRotationAngle: Double = 0.0
    ) {
        self.id = id
        self.setupName = setupName
        self.client = client
        self.project = project
        self.notes = notes
        self.subjectHeight = subjectHeight
        self.subjectHorizontalAim = subjectHorizontalAim
        self.subjectRotationAngle = subjectRotationAngle
    }
}

extension Setup {

    /// Rotates all equipment around the subject (0, 0) so that the first camera sits at 6 o'clock.
    /// All other equipment follows with relative positions and distances preserved.
    /// Called once upon scan completion to establish the initial camera baseline.
    /// Rotate every equipment pointing to subject
    func alignAndOrientDiagram() {
        guard let firstCamera = nodes.first(where: { $0.category == .camera }) else { return }

        let cameraPosX = firstCamera.positionX
        let cameraPosY = firstCamera.positionY
        guard abs(cameraPosX) > 0.001 || abs(cameraPosY) > 0.001 else { return }

        // In screen coordinates (+Y is down), 6 o'clock is +pi/2 radians (90 degrees)
        let currentAngle = atan2(cameraPosY, cameraPosX)
        let deltaAngle = (Double.pi / 2.0) - currentAngle

        let cosDelta = cos(deltaAngle)
        let sinDelta = sin(deltaAngle)

        for node in nodes {
            let oldX = node.positionX
            let oldY = node.positionY

            // 2D rotation matrix around (0, 0)
            let newX = oldX * cosDelta - oldY * sinDelta
            let newY = oldX * sinDelta + oldY * cosDelta

            node.positionX = newX
            node.positionY = newY

            node.syncDistanceFromPosition()
        }

        for node in nodes {
            node.pointToSubject()
        }
    }

    /// The earliest reference photo, the same one the setup's detail screen shows first.
    var coverImage: ReferenceImage? {
        referenceImages.min { $0.createdAt < $1.createdAt }
    }

    /// "SS" for "Skincare / soft daylight": shown instead of a cover photo when there is none.
    var initials: String {
        let words = setupName.split(whereSeparator: { $0 == " " || $0 == "/" }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    /// Updates `subjectHorizontalAim` string (e.g. "45") from `subjectRotationAngle`
    func syncSubjectHorizontalAimFromRotation() {
        let displayAngle = (360 - Int(subjectRotationAngle)) % 360
        self.subjectHorizontalAim = "\(displayAngle)"
    }

    /// Updates `subjectRotationAngle` from a typed numeric `subjectHorizontalAim` string
    func syncSubjectRotationFromHorizontalAim() {
        let normalized = subjectHorizontalAim.replacingOccurrences(of: ",", with: ".")
        let cleaned = normalized.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        if let displayAngle = Double(cleaned) {
            let rawAngle = (360.0 - displayAngle).truncatingRemainder(dividingBy: 360.0)
            self.subjectRotationAngle = rawAngle < 0 ? rawAngle + 360.0 : rawAngle
        }
    }
}
