import SwiftUI

/// Add or edit one item: light, modifier or camera (Sketch R05, R06, R06c · A10-7, A10-11).
struct EquipmentView: View {
    @State private var viewModel = EquipmentViewModel()

    var body: some View {
        Text("Equipment")
    }
}

#Preview {
    EquipmentView()
}
