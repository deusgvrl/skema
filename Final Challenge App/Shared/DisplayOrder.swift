import Foundation

/// The order setups show their equipment and photos in (A10-96). The PDF table reuses it (A10-98).
enum DisplayOrder {
    /// Lights first, then accessories, then cameras; inside a type, by label like numbers (L2 before L10).
    /// SwiftData does not keep the order of a list, so the order is rebuilt from the values every time.
    static func equipment(_ items: [Equipment]) -> [Equipment] {
        items.sorted { first, second in
            let firstRank = rank(of: first.category)
            let secondRank = rank(of: second.category)
            if firstRank != secondRank {
                return firstRank < secondRank
            }
            return sortKey(of: first).localizedStandardCompare(sortKey(of: second)) == .orderedAscending
        }
    }

    /// Oldest added first, so "Reference 1, 2, 3" stays stable.
    static func photos(_ images: [ReferenceImage]) -> [ReferenceImage] {
        images.sorted { $0.createdAt < $1.createdAt }
    }

    /// Where a type sits in the list.
    static func rank(of category: EquipmentCategory) -> Int {
        switch category {
        case .light: return 0
        case .accessory: return 1
        case .camera: return 2
        }
    }

    /// The label, or the name when the label is empty, so unlabeled items still sit in a sensible place.
    private static func sortKey(of item: Equipment) -> String {
        let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? item.name : label
    }
}
