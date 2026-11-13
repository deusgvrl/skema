//
//  EquipmentCarousel.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 13/11/26.
//

import SwiftUI

struct EquipmentCarousel: View {
    let viewModel: ReviewViewModel
    var isReadOnly: Bool = false
    var onNodeTap: ((Equipment) -> Void)? = nil
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.nodes) { node in
                    VStack(alignment: .leading) {
                        Text("\(node.name)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .onTapGesture {
                        onNodeTap?(node)
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemBackground))
    }
}


#Preview {
    EquipmentCarousel(viewModel: ReviewViewModel())
}
