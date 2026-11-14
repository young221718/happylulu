import SwiftUI

// Shared visual roles for settings; typography and spacing stay the same across themes.
enum SettingsLayout {
    static let titleToCard: CGFloat = 10
    static let betweenSections: CGFloat = 24
    static let rowHorizontal: CGFloat = 14
    static let rowVertical: CGFloat = 12
    static let bodyFont = Font.system(size: 13)
    static let sectionFont = Font.system(size: 13, weight: .medium)
    static let detailFont = Font.system(size: 11)
}
