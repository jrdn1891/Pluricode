import AppKit
import Metal

enum AppearanceMode: String, CaseIterable {
    case light, dark, system

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .system: "circle.lefthalf.filled"
        }
    }

    func apply() {
        switch self {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }
}

struct Theme {
    let isDark: Bool

    init(from appearance: NSAppearance) {
        isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    var canvasClearColor: MTLClearColor {
        isDark ? MTLClearColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
               : MTLClearColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
    }

    var terminalNodeColor: SIMD4<Float> {
        isDark ? SIMD4(0.14, 0.14, 0.18, 1) : SIMD4(0.90, 0.91, 0.94, 1)
    }

    var taskCardNodeColor: SIMD4<Float> {
        isDark ? SIMD4(0.20, 0.20, 0.25, 1) : SIMD4(1.0, 1.0, 1.0, 1)
    }

    var sectionNodeColor: SIMD4<Float> {
        isDark ? SIMD4(0.11, 0.11, 0.14, 1) : SIMD4(0.93, 0.93, 0.96, 1)
    }

    var sectionHighlightColor: SIMD4<Float> {
        isDark ? SIMD4(0.14, 0.16, 0.22, 1) : SIMD4(0.88, 0.90, 0.97, 1)
    }

    var sectionDividerColor: SIMD4<Float> {
        isDark ? SIMD4(0.25, 0.25, 0.30, 0.6) : SIMD4(0.78, 0.78, 0.82, 0.6)
    }

    var minimapBackground: SIMD4<Float> {
        isDark ? SIMD4(0.12, 0.12, 0.15, 0.85) : SIMD4(0.90, 0.90, 0.92, 0.85)
    }

    var minimapViewportFrame: SIMD4<Float> {
        isDark ? SIMD4(1, 1, 1, 0.25) : SIMD4(0, 0, 0, 0.3)
    }

    var terminalBackground: NSColor {
        isDark ? NSColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1)
               : NSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    }

    var terminalForeground: NSColor {
        isDark ? .white : NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
    }
}
