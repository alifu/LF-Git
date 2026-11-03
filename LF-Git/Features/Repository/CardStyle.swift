import SwiftUI

/// Shapes and sizes shared by the window's cards, side menu and pills.
enum Chrome {
    static let cardRadius: CGFloat = 10
    static let pillRadius: CGFloat = 7
    static let pillHeight: CGFloat = 26
    static let tileRadius: CGFloat = 8
    /// Space between the window edge, the side menu and the cards.
    static let gutter: CGFloat = 8
}

extension View {
    /// A white rounded card with a hairline border: the list and detail panes of a repository window.
    func lfCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: Chrome.cardRadius))
            .background(RoundedRectangle(cornerRadius: Chrome.cardRadius).fill(.theme(.background)))
            .overlay(RoundedRectangle(cornerRadius: Chrome.cardRadius).strokeBorder(.theme(.border)))
    }
}

/// A count in a small dark capsule, as next to a card title or on a side-menu tile.
struct CountCapsule: View {
    let count: Int
    var fill: LFThemeToken = .text

    var body: some View {
        Text("\(count)")
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.theme(.background))
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(.theme(fill)))
            .accessibilityHidden(true)
    }
}

/// A card's title row: a symbol, a title and an optional count, on the window color with a rule underneath.
struct CardHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    var count: Int?
    let trailing: Trailing

    init(_ title: String, symbol: String, count: Int? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.symbol = symbol
        self.count = count
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.theme(.textSubtle))
            Text(title).font(.body.weight(.medium)).foregroundStyle(.theme(.text))
            if let count { CountCapsule(count: count) }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.theme(.surfaceSunken))
        .overlay(alignment: .bottom) { Rectangle().fill(.theme(.border)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// The dotted canvas behind empty detail panes.
struct DotGridBackground: View {
    private static let spacing: CGFloat = 6
    private static let dot: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y = Self.spacing / 2
            while y < size.height {
                var x = Self.spacing / 2
                while x < size.width {
                    dots.addRect(CGRect(x: x, y: y, width: Self.dot, height: Self.dot))
                    x += Self.spacing
                }
                y += Self.spacing
            }
            context.fill(dots, with: .color(.theme(.borderStrong).opacity(0.55)))
        }
        .background(.theme(.surfaceSunken))
        .accessibilityHidden(true)
    }
}

/// A centred message for an empty pane: symbol, title and a line of help, in the side-menu style.
struct EmptyPane<Actions: View>: View {
    let title: String
    let symbol: String
    let message: String
    let actions: Actions

    init(_ title: String, symbol: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.symbol = symbol
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.theme(.borderStrong))
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 12).fill(.theme(.surfaceSunken)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.theme(.border)))
            Text(title).font(.headline).foregroundStyle(.theme(.text))
            Text(message)
                .font(.callout)
                .foregroundStyle(.theme(.textSubtle))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            actions.buttonStyle(.link)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Card pieces") {
    HStack(spacing: Chrome.gutter) {
        VStack(spacing: 0) {
            CardHeader("Changes", symbol: "square.split.2x1", count: 3)
            Spacer()
        }
        .frame(width: 280)
        .lfCard()
        EmptyPane("No branch selected", symbol: "arrow.triangle.branch", message: "Choose a branch in the list.")
            .background(DotGridBackground())
            .lfCard()
    }
    .padding(Chrome.gutter)
    .frame(width: 800, height: 400)
    .background(.theme(.surfaceSunken))
}
#endif
