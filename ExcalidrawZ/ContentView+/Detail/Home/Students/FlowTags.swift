//
//  FlowTags.swift
//  ExcalidrawZ
//
//  Capsule tag row used by the student editor.
//

import SwiftUI

struct FlowTags: View {
    var tags: [String]
    var onRemove: ((String) -> Void)?

    var body: some View {
        if tags.isEmpty {
            Text("No topics yet").font(.callout).foregroundStyle(.tertiary)
        } else {
            FlowLayoutStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag).font(.callout)
                        if let onRemove {
                            Button { onRemove(tag) } label: { Image(systemSymbol: .xmark).font(.caption2) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}
struct FlowLayoutStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
