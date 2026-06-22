import SwiftUI

struct AttachmentChipsOverlay: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                ForEach(session.pendingAttachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        session.removeAttachment(id: attachment.id)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .allowsHitTesting(!session.pendingAttachments.isEmpty)
        .animation(.easeInOut(duration: 0.15), value: session.pendingAttachments)
    }
}

private struct AttachmentChip: View {
    let attachment: PendingImageAttachment
    let onRemove: () -> Void
    @State private var hovering = false
    @State private var previewing = false

    var body: some View {
        HStack(spacing: 6) {
            Button { previewing = true } label: {
                HStack(spacing: 6) {
                    thumbnail
                    Text(attachment.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 140)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $previewing, arrowEdge: .bottom) { preview }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let nsImage = attachment.thumbnail {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "photo")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let nsImage = attachment.thumbnail {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 400, maxHeight: 400)
                .padding(8)
        }
    }
}
