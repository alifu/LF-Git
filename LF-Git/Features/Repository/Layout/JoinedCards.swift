import SwiftUI

/// Two panes flush inside one card, split by a hairline (the Figma "Branches" layout: commits │ preview).
/// The leading pane has a fixed width range; the trailing one takes the rest.
struct JoinedCards<Leading: View, Trailing: View>: View {
    var leadingWidth: ClosedRange<CGFloat> = Chrome.listColumn...Chrome.listColumnMax
    let leading: Leading
    let trailing: Trailing

    init(leadingWidth: ClosedRange<CGFloat> = Chrome.listColumn...Chrome.listColumnMax,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leadingWidth = leadingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(minWidth: leadingWidth.lowerBound, idealWidth: leadingWidth.lowerBound,
                       maxWidth: leadingWidth.upperBound, maxHeight: .infinity)
            Rectangle().fill(.theme(.border)).frame(width: 1)
            trailing
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.theme(.background))
    }
}

/// A ✕ for a card header or a panel that can be closed. No Esc shortcut on purpose: `.cancelAction` is a
/// window-wide key equivalent and would close the panel while Esc is meant for the commit message or the palette.
struct CloseButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "xmark") }
            .buttonStyle(.borderless)
            .help(label)
            .accessibilityLabel(label)
    }
}

#if DEBUG
#Preview("Joined cards") {
    JoinedCards {
        CardHeader("Commits", symbol: "clock", count: 12)
    } trailing: {
        EmptyPane("Nothing selected", symbol: "doc.text", message: "Select something to preview.")
            .background(DotGridBackground())
    }
    .lfCard()
    .padding(Chrome.gutter)
    .frame(width: 900, height: 500)
    .background(.theme(.surfaceSunken))
}
#endif
