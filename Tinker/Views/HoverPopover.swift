//
//  HoverPopover.swift
//  Tinker
//

import SwiftUI

/// Tinker's tooltip: a small popover that appears while the pointer rests on a view.
struct HoverPopoverModifier: ViewModifier {
    let text: Text

    @State private var isPresented = false
    @State private var pendingShow: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                pendingShow?.cancel()
                if isHovering {
                    // A short wait keeps popovers from flashing as the pointer crosses a row.
                    pendingShow = Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        if !Task.isCancelled { isPresented = true }
                    }
                } else {
                    isPresented = false
                }
            }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                text
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
    }
}

extension View {
    func hoverPopover(_ text: Text) -> some View {
        modifier(HoverPopoverModifier(text: text))
    }

    func hoverPopover(_ text: LocalizedStringKey) -> some View {
        modifier(HoverPopoverModifier(text: Text(text)))
    }
}

/// The small "i" beside a label that explains it on hover.
struct InfoButton: View {
    let text: Text

    var body: some View {
        Image(systemName: "info.circle.fill")
            .foregroundStyle(.secondary)
            .hoverPopover(text)
            .accessibilityLabel(text)
    }
}
