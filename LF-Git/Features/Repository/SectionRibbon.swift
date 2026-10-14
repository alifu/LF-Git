import LFKit
import SwiftUI

/// The repository's sections as a ribbon, like Office 2007: Changes and History as big buttons, the rest as
/// medium ones in a block, a group caption underneath, and a tab strip that minimises the ribbon (double-click
/// the tab or use the arrow); minimised, the strip keeps one small button per section.
struct SectionRibbon: View {
    let repository: RepositoryModel
    @AppStorage("ribbon.isCollapsed") private var isCollapsed = false

    private static let bigSections: [RepositorySection] = [.changes, .history]
    private static let mediumRows = 3

    private var mediumSections: [RepositorySection] { RepositorySection.allCases.filter { !Self.bigSections.contains($0) } }

    /// The medium buttons in columns of `mediumRows`, so the block reads top to bottom, then left to right.
    private var mediumColumns: [[RepositorySection]] {
        stride(from: 0, to: mediumSections.count, by: Self.mediumRows).map {
            Array(mediumSections[$0..<min($0 + Self.mediumRows, mediumSections.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            if !isCollapsed {
                Divider()
                WrappingLayout(spacing: 0, lineSpacing: 4) {
                    group("Main") {
                        ForEach(Self.bigSections) { bigButton($0) }
                    }
                    separator
                    group("Browse") {
                        ForEach(Array(mediumColumns.enumerated()), id: \.offset) { _, column in
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(column) { mediumButton($0) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .padding(.trailing, Self.toggleSize) // keeps the groups clear of the corner button
                
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(.theme(.surfaceRaised)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.theme(.border)))
        .overlay(alignment: .bottomTrailing) { toggleButton }
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("section-picker")
    }

    private static let toggleSize: CGFloat = 26

    /// A vertical rule between two groups. It is a layout child of its own with a fixed height (a big button plus
    /// its caption), so it cannot collapse to nothing the way an overlay or a Divider can.
    private var separator: some View {
        Rectangle()
            .fill(.theme(.textSubtle).opacity(0.45))
            .frame(width: 1, height: 84)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }

    /// Bottom right, where Office keeps its "minimize" arrow.
    private var toggleButton: some View {
        Button(action: toggle) {
            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                .font(.caption.weight(.semibold))
                .frame(width: Self.toggleSize, height: Self.toggleSize - 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.theme(.textSubtle))
        .help(isCollapsed ? "Expand the ribbon" : "Minimize the ribbon")
        .accessibilityLabel(isCollapsed ? "Expand the ribbon" : "Minimize the ribbon")
        .accessibilityIdentifier("ribbon-toggle")
        .padding(2)
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: 8) {
            Text("Repository")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.theme(.accentText))
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(.theme(isCollapsed ? .surfaceRaised : .background)))
                .onTapGesture(count: 2) { toggle() }
                .help("Double-click to \(isCollapsed ? "show" : "minimize") the ribbon")
                .accessibilityIdentifier("ribbon-tab")
            if isCollapsed {
                ForEach(RepositorySection.allCases) { smallButton($0) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .padding(.trailing, Self.toggleSize)
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: 0.15)) { isCollapsed.toggle() }
    }

    // MARK: - Groups and buttons

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 2, content: content)
            Spacer()
            Divider().padding(.vertical, 4)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.theme(.textSubtle))
                .frame(height: 16)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 6)
    }

    private func bigButton(_ section: RepositorySection) -> some View {
        RibbonButton(section: section, isSelected: repository.section == section, size: .big, count: count(section)) {
            repository.section = section
        }
    }

    private func mediumButton(_ section: RepositorySection) -> some View {
        RibbonButton(section: section, isSelected: repository.section == section, size: .medium, count: count(section)) {
            repository.section = section
        }
    }

    private func smallButton(_ section: RepositorySection) -> some View {
        RibbonButton(section: section, isSelected: repository.section == section, size: .small, count: count(section)) {
            repository.section = section
        }
    }

    private func count(_ section: RepositorySection) -> Int {
        switch section {
        case .changes: repository.status.entries.filter { $0.kind != .unmerged }.count
        case .stash: repository.stashes.count
        case .conflicts: repository.files.count
        default: 0
        }
    }
}

/// One ribbon button: a big icon over its name, a medium icon beside it, or the icon alone.
private struct RibbonButton: View {
    enum Size { case big, medium, small }

    let section: RepositorySection
    let isSelected: Bool
    let size: Size
    let count: Int
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            switch size {
            case .big:
                VStack(spacing: 3) {
                    Image(systemName: section.symbol).font(.system(size: 26)).frame(height: 30)
                    Text(section.rawValue).font(.callout).lineLimit(1)
                }
                .frame(width: 70, height: 66)
                .overlay(alignment: .topTrailing) { badge }
                .contentShape(Rectangle())
            case .medium:
                HStack(spacing: 6) {
                    Image(systemName: section.symbol).font(.system(size: 14)).frame(width: 18)
                    Text(section.rawValue).font(.callout).lineLimit(1)
                    Spacer(minLength: 2)
                    badge
                }
                .padding(.horizontal, 6)
                .frame(width: 118, height: 20, alignment: .leading)
                .contentShape(Rectangle())
            case .small:
                Image(systemName: section.symbol)
                    .font(.system(size: 13))
                    .frame(width: 24, height: 20)
                    .overlay(alignment: .topTrailing) { badge.scaleEffect(0.8, anchor: .topTrailing) }
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.theme(isSelected ? .accentText : .text))
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.theme(isSelected ? .accentSubtle : (isHovering ? .background : .surfaceRaised)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.theme(isSelected || isHovering ? .border : .surfaceRaised)))
        )
        .onHover { isHovering = $0 }
        .help(section.rawValue)
        .accessibilityLabel(section.rawValue)
        .accessibilityValue(count > 0 ? "\(count)" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("section-\(section.rawValue)")
    }

    @ViewBuilder
    private var badge: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.theme(.accentText))
        }
    }
}

#if DEBUG
#Preview("Section ribbon") {
    PreviewRepository(width: 800, height: 140) { repository, app in
        SectionRibbon(repository: repository)
    }
}
#endif

/// Lays its children out in rows, starting a new row when the next child does not fit: a narrow window wraps the
/// ribbon's groups instead of cutting them off.
private struct WrappingLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(in: proposal.width ?? .infinity, subviews: subviews)
        // Takes the whole width offered (children start at the left edge); only an unbounded proposal shrinks to fit.
        let width = proposal.width ?? (rows.map { $0.width }.max() ?? 0)
        return CGSize(width: width, height: rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + gap + size.width > maxWidth {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += (rows[last].indices.isEmpty ? 0 : spacing) + size.width
            rows[last].height = max(rows[last].height, size.height)
            rows[last].indices.append(index)
        }
        return rows
    }
}
