import LFKit
import SwiftUI

/// Which sections the side menu lists, in order: the everyday ones on top, the rest below a rule.
/// Conflicts only shows while something is conflicted, or while it is the section on screen.
struct SideMenuSections: Equatable {
    private static let primarySections: [RepositorySection] = [.changes, .branches, .history]

    let primary: [RepositorySection]
    let more: [RepositorySection]

    init(hasConflicts: Bool, selected: RepositorySection) {
        primary = Self.primarySections
        let rest = RepositorySection.allCases.filter { !Self.primarySections.contains($0) && $0 != .conflicts }
        more = hasConflicts || selected == .conflicts ? rest + [.conflicts] : rest
    }
}

/// The repository's sections as a column of icon tiles down the left of the window, with Settings, the Git
/// account and the log panel pinned at the bottom. A small accent mark on the window edge follows the selection.
struct SectionRail: View {
    @Bindable var repository: RepositoryModel
    @Namespace private var marker
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general.rawValue

    static let width: CGFloat = SideMenuTile.size + Chrome.gutter * 2

    private var sections: SideMenuSections {
        SideMenuSections(hasConflicts: !repository.files.isEmpty, selected: repository.section)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Chrome.gutter) {
                    ForEach(sections.primary) { tile($0) }
                    Rectangle().fill(.theme(.border)).frame(width: 18, height: 1).padding(.vertical, 2)
                    ForEach(sections.more) { tile($0) }
                }
                // The scroll view clips its content, so the first tile's badge (Changes) needs room above it.
                .padding(.top, SideMenuTile.badgeOverhang + 2)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("section-picker")
            Spacer(minLength: Chrome.gutter)
            bottomGroup
        }
        .padding(.bottom, Chrome.gutter * 1.5)
        .frame(width: Self.width)
        .animation(.easeInOut(duration: 0.18), value: repository.section)
    }

    private func tile(_ section: RepositorySection) -> some View {
        let isSelected = repository.section == section
        return SideMenuTile(
            symbol: section.symbol, title: section.rawValue, isSelected: isSelected,
            count: repository.badgeCount(for: section), countFill: section == .conflicts ? .danger : .text,
            identifier: "section-\(section.rawValue)"
        ) {
            repository.section = section
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(.theme(.accentVivid))
                    .frame(width: 5, height: 20)
                    .offset(x: -(Chrome.gutter + 2.5))
                    .matchedGeometryEffect(id: "marker", in: marker)
                    .accessibilityHidden(true)
            }
        }
    }

    private var bottomGroup: some View {
        VStack(spacing: Chrome.gutter) {
            SideMenuTile(symbol: "terminal", title: "Log", isSelected: repository.showsLogPanel,
                         identifier: "log-button", help: "Show or hide the log panel (⇧⌘L)") {
                repository.showsLogPanel.toggle()
            }
            SideMenuTile(symbol: "gearshape", title: "Settings", identifier: "settings-button", help: "Settings (⌘,)") {
                settingsTab = SettingsTab.general.rawValue
                openSettings()
            }
            accountButton
        }
    }

    /// The Git account, as a filled accent circle like an avatar; opens Settings on the Account tab.
    private var accountButton: some View {
        Button {
            settingsTab = SettingsTab.account.rawValue
            openSettings()
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.theme(.onAccent))
                .frame(width: SideMenuTile.size, height: SideMenuTile.size)
                .background(Circle().fill(.theme(.accent)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Git account: commit author and sign-ins")
        .accessibilityLabel("Git account")
        .accessibilityIdentifier("account-button")
    }
}

extension RepositoryModel {
    /// The number a section shows on its tile and card header: changed files, stashes or conflicted files.
    func badgeCount(for section: RepositorySection) -> Int {
        switch section {
        case .changes: status.entries.filter { $0.kind != .unmerged }.count
        case .stash: stashes.count
        case .conflicts: files.count
        default: 0
        }
    }
}

/// One square tile of the side menu: an outlined icon, raised and tinted when selected, with an optional count.
struct SideMenuTile: View {
    static let size: CGFloat = 34
    /// How far the count badge sticks out above the tile's top edge.
    static let badgeOverhang: CGFloat = 5

    let symbol: String
    let title: String
    var isSelected = false
    var count = 0
    var countFill: LFThemeToken = .text
    let identifier: String
    var help: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.theme(isSelected ? .railSelectedIcon : (isHovering ? .text : .textSubtle)))
                .frame(width: Self.size, height: Self.size)
                .background(RoundedRectangle(cornerRadius: Chrome.tileRadius).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: Chrome.tileRadius).strokeBorder(.theme(.border)))
                .shadow(color: .black.opacity(isSelected ? 0.06 : 0), radius: 1, y: 1)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        CountCapsule(count: count, fill: countFill).offset(x: 6, y: -Self.badgeOverhang)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Chrome.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? "\(count)" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var fill: Color {
        if isSelected { return .theme(.surfaceRaised) }
        return isHovering ? .theme(.surfaceRaised).opacity(0.6) : .clear
    }
}

#if DEBUG
#Preview("Side menu") {
    PreviewRepository(width: 80, height: 620) { repository, _ in
        SectionRail(repository: repository)
            .background(.theme(.surfaceSunken))
    }
}
#endif
