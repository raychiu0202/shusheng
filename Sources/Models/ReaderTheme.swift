import SwiftUI
import UIKit

/// 阅读背景主题：白纸 / 米黄 / 夜间
enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper
    case sepia
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "白纸"
        case .sepia: return "米黄"
        case .night: return "夜间"
        }
    }

    var background: Color {
        switch self {
        case .paper: return .white
        case .sepia: return Color(red: 0.97, green: 0.94, blue: 0.87)
        case .night: return Color(red: 0.12, green: 0.12, blue: 0.13)
        }
    }

    /// 正文颜色（UITextView 不支持 SwiftUI Color，直接用 UIKit 色）
    var textColor: UIColor {
        switch self {
        case .paper: return .label
        case .sepia: return UIColor(red: 0.22, green: 0.17, blue: 0.11, alpha: 1)
        case .night: return UIColor(white: 0.92, alpha: 1)
        }
    }

    var colorScheme: ColorScheme {
        self == .night ? .dark : .light
    }
}
