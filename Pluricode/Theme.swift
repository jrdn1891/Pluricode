import AppKit
import Metal
import SwiftTerm

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

    var terminalHighlightColor: SIMD4<Float> {
        isDark ? SIMD4(0.16, 0.20, 0.26, 1) : SIMD4(0.84, 0.88, 0.96, 1)
    }

    var minimapBackground: SIMD4<Float> {
        isDark ? SIMD4(0.12, 0.12, 0.15, 0.85) : SIMD4(0.90, 0.90, 0.92, 0.85)
    }

    var minimapViewportFrame: SIMD4<Float> {
        isDark ? SIMD4(1, 1, 1, 0.25) : SIMD4(0, 0, 0, 0.3)
    }

    var terminalBackground: NSColor {
        isDark ? NSColor(red: 36/255, green: 41/255, blue: 44/255, alpha: 1)
               : NSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    }

    var terminalForeground: NSColor {
        isDark ? .white : NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
    }

    var terminalPalette: [SwiftTerm.Color] {
        isDark ? [
            rgb(0x1D1F21), rgb(0xCC6666), rgb(0xB5BD68), rgb(0xF0C674),
            rgb(0x81A2BE), rgb(0xB294BB), rgb(0x8ABEB7), rgb(0xC5C8C6),
            rgb(0x666666), rgb(0xD54E53), rgb(0xB9CA4A), rgb(0xE7C547),
            rgb(0x7AA6DA), rgb(0xC397D8), rgb(0x70C0B1), rgb(0xEAEAEA),
        ] : [
            rgb(0x4D4D4C), rgb(0xC82829), rgb(0x718C00), rgb(0xEAB700),
            rgb(0x4271AE), rgb(0x8959A8), rgb(0x3E999F), rgb(0xD6D6D6),
            rgb(0x8E908C), rgb(0xF5871F), rgb(0x8AB42C), rgb(0xF4BF4F),
            rgb(0x6B91D0), rgb(0xA37ABA), rgb(0x66B5BB), rgb(0xFFFFFF),
        ]
    }
}

private func rgb(_ value: UInt32) -> SwiftTerm.Color {
    SwiftTerm.Color(
        red:   UInt16((value >> 16) & 0xFF) * 0x101,
        green: UInt16((value >> 8) & 0xFF) * 0x101,
        blue:  UInt16(value & 0xFF) * 0x101
    )
}
