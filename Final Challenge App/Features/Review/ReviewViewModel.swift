import Observation
import SwiftUI

/// State and actions for ReviewView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.

@Observable
final class ReviewViewModel {
    var nodes: [Equipment] = []
    var draftSetup: Setup
    
    var canUndo = false
    var canRedo = false
    
    init(setup: Setup? = nil) {
        if let existingSetup = setup {
            // It receives the setup passed from LoadingPageView!
            self.draftSetup = existingSetup
            self.nodes = existingSetup.nodes
        } else {
            self.draftSetup = Setup(setupName: "New Setup")
            self.nodes = []
        }
    }
    
    func updateUndoState(undoManager: UndoManager?) {
        self.canUndo = undoManager?.canUndo ?? false
        self.canRedo = undoManager?.canRedo ?? false
    }

    func applyStateChange(oldNodes: [Equipment], undoManager: UndoManager?) {
        let currentNodes = self.nodes
        undoManager?.registerUndo(withTarget: self) { target in
            target.applyStateChange(oldNodes: currentNodes, undoManager: undoManager)
            target.nodes = oldNodes
            target.updateUndoState(undoManager: undoManager)
        }
        updateUndoState(undoManager: undoManager)
    }
}




// @Observable
//final class ReviewViewModel {
//    
//    var nodes: [Equipment] = []
//    var projectDetails = Setup(
//        setupName: "Skincare / soft daylight",
//        client: "Aesop",
//        project: "November catalog",
//        notes: "Keep the bottle label square to camera. Flag the key light to control the reflection on the cap. Mark tripod feet with tape."
//    )
//    
//    // Undo/Redo State
//    var canUndo = false
//    var canRedo = false
//    
//    init() {
//            // Dummy Data for R04 / R08
//            self.nodes = [
//                Equipment(
//                    category: .light,
//                    label: "L1", name: "Profoto D2 500", role: "Key",
//                    position: CGPoint(x: -120, y: -100),
//                    power: "7.0", colorTemp: "5600 K",
//                    height: "130 cm", tilt: "35°", horizontalAim: "135°", distance: "1.35 m",
//                    rotationAngle: 45, accessories: "90 cm octabox"
//                ),
//                Equipment(
//                    category: .light,
//                    label: "L2", name: "Fill Light", role: "Fill",
//                    position: CGPoint(x: 100, y: -30),
//                    power: "5.0", colorTemp: "5600 K",
//                    height: "120 cm", tilt: "20°", horizontalAim: "45°", distance: "1.23 m",
//                    rotationAngle: 330, accessories: "Umbrella"
//                ),
//                Equipment(
//                    category: .light,
//                    label: "L3", name: "Rim Light", role: "Rim",
//                    position: CGPoint(x: 120, y: -150),
//                    power: "6.0", colorTemp: "5600 K",
//                    height: "180 cm", tilt: "45°", horizontalAim: "-45°", distance: "1.78 m",
//                    rotationAngle: 300, accessories: "Bare bulb"
//                ),
//                Equipment(
//                    category: .light,
//                    label: "L4", name: "Background", role: "Background",
//                    position: CGPoint(x: -80, y: -200),
//                    power: "4.0", colorTemp: "5600 K",
//                    height: "100 cm", tilt: "0°", horizontalAim: "0°", distance: "1.80 m",
//                    rotationAngle: 120, accessories: "Snoot"
//                ),
//                Equipment(
//                    category: .camera,
//                    label: "C1", name: "Canon EOS R5", role: "Main Camera",
//                    position: CGPoint(x: 0, y: 150), // Positioned at the bottom center
//                    power: "", colorTemp: "", // Lights only
//                    lens: "RF 50mm f/1.2", iso: "100", aperture: "f/5.6", shutterSpeed: "1/125", whiteBalance: "5600 K",
//                    height: "110 cm", tilt: "0°", horizontalAim: "0°", distance: "1.50 m",
//                    rotationAngle: 0, accessories: "Tether cable", notes: "Keep low angle"
//                )
//            ]
//        }
//    
//    // MARK: Undo/Redo Registration
//    
//    func updateUndoState(undoManager: UndoManager?) {
//        self.canUndo = undoManager?.canUndo ?? false
//        self.canRedo = undoManager?.canRedo ?? false
//    }
//    
//    func applyStateChange(oldNodes: [Equipment], undoManager: UndoManager?) {
//        let currentNodes = self.nodes
//        
//        undoManager?.registerUndo(withTarget: self) { target in
//            target.applyStateChange(oldNodes: currentNodes, undoManager: undoManager)
//            target.nodes = oldNodes
//            target.updateUndoState(undoManager: undoManager)
//        }
//        
//        updateUndoState(undoManager: undoManager)
//    }
//}
