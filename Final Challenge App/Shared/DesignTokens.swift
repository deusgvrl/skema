//
//  DesignTokens.swift
//  Final Challenge App
//

import SwiftUI

enum DesignTokens {
    static let accentPrimary = Color("AccentPrimary")
    /// Red text (links, the category value in equipment sheets). Light is AccentPrimary; dark is lighter
    /// than Sketch's #FF5A4A, which is only 3.5:1 on the form rows.
    static let accentText = Color("AccentText")
    /// Opaque sheet surface (Sketch R02 "Sheet chrome").
    static let sheetBackground = Color("SheetBackground")
    /// Grouped row surface inside sheets (Sketch R06 rows).
    static let formRowBackground = Color("FormRowBackground")

    // MARK: Diagram (Sketch R04)
    static let diagramGrid = Color("DiagramGrid")
    /// Dashed lines from the subject to each item. Decorative: the distance text carries the value.
    static let diagramGuide = Color("DiagramGuide")
    /// Equipment outlines, light heads and camera bodies.
    static let diagramStroke = Color("DiagramStroke")
    static let diagramNodeFill = Color("DiagramNodeFill")
    /// Warm glow behind lights; use as the centre stop of a radial gradient fading to clear.
    static let diagramGlow = Color("DiagramGlow")
    static let diagramSubjectFill = Color("DiagramSubjectFill")
    static let diagramSubjectBorder = Color("DiagramSubjectBorder")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let glassCardFill = Color("GlassCardFill")
    static let nodeDetailFill = Color("NodeDetailFill")
    static let pageBackground = Color("PageBackground")
    /// A fixed dark chip in both appearances, like the Sketch R01v toast.
    static let toastBackground = Color.black
    static let glassCardBorder = Color("GlassCardBorder")
    static let glassControlFill = Color("GlassControlFill")
    static let glassControlBorderTop = Color("GlassControlBorderTop")
    static let glassControlBorderBottom = Color("GlassControlBorderBottom")

    static var scrimGradient: LinearGradient {
        LinearGradient(
            colors: [Color("ScrimGradientTop"), Color("ScrimGradientMid"), Color("ScrimGradientBottom")],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
