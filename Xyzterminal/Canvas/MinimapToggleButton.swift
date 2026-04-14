import SwiftUI

struct MinimapToggleButton: View {
    let document: CanvasDocument

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    document.minimapCollapsed.toggle()
                } label: {
                    Image(systemName: document.minimapCollapsed ? "map" : "rectangle.bottomright.inset.filled")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
    }
}
