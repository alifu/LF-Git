import SwiftUI

/// Sizes of the hero layout. Text 440 + spacing 32 + panel 400 fits from about 880 points. The text column is fixed:
/// given only a maximum it was squeezed by the side panel until the action buttons wrapped their titles.
private enum HeroMetrics {
    static let textWidth: CGFloat = 440
    static let columnSpacing: CGFloat = 32
    static let panelWidth: CGFloat = 400
    static let panelMaxHeight: CGFloat = 460
    static let panelHeight: CGFloat = 220
    static let panelRadius: CGFloat = 16
    static let symbolSize: CGFloat = 120
}

/// A full-width state with no list: a title, a message and actions on the left, a symbol on a tinted side panel on the right.
/// Narrower than about 880 points, the panel moves under the text.
struct HeroPane<Actions: View>: View {
    let title: String
    let message: String
    let symbol: String
    let actions: Actions

    init(title: String, message: String, symbol: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: HeroMetrics.columnSpacing) {
                textColumn
                    .frame(width: HeroMetrics.textWidth, alignment: .leading)
                sidePanel
                    .frame(width: HeroMetrics.panelWidth)
                    .frame(maxHeight: HeroMetrics.panelMaxHeight)
            }
            VStack(alignment: .leading, spacing: HeroMetrics.columnSpacing) {
                textColumn
                sidePanel
                    .frame(maxWidth: .infinity)
                    .frame(height: HeroMetrics.panelHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.theme(.text))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.theme(.textSubtle))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                actions
            }
            .padding(.top, 4)
        }
    }

    private var sidePanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HeroMetrics.panelRadius)
                .fill(.theme(.accentSubtle))
            Image(systemName: symbol)
                .font(.system(size: HeroMetrics.symbolSize, weight: .light))
                .foregroundStyle(.theme(.accentText))
                .accessibilityHidden(true)
        }
    }
}

#Preview("Wide") {
    HeroPane(title: "Looks like you have no repositories yet",
             message: "Open a repository or clone one to start. It shows up in the list afterwards.",
             symbol: "arrow.triangle.branch") {
        Button("Open Repository…") {}
        Button("Clone Repository…") {}
    }
    .padding(28)
    .frame(width: 960, height: 420)
    .background(.theme(.surfaceSunken))
}

#Preview("Narrow") {
    HeroPane(title: "Looks like you have no repositories yet",
             message: "Open a repository or clone one to start. It shows up in the list afterwards.",
             symbol: "arrow.triangle.branch") {
        Button("Open Repository…") {}
        Button("Clone Repository…") {}
    }
    .padding(28)
    .frame(width: 520, height: 560)
    .background(.theme(.surfaceSunken))
}
