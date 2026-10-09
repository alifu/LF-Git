import AppKit
import LFKit

enum EditorMetrics {
    /// One fixed height for every row keeps scrolling O(1) for millions of lines.
    static let rowHeight: CGFloat = 20
    static let contentWidth: CGFloat = 2600
    static let gutterPadding: CGFloat = 10
    static let focusBarWidth: CGFloat = 3
    static let dimmedAlpha: CGFloat = 0.38
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let gutterFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let headerFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
}

/// Draws a row's background from a theme token at draw time, so light/dark switches need no reload.
final class ConflictRowView: NSTableRowView {
    var background: LFThemeToken?
    var focused = false

    override func drawBackground(in dirtyRect: NSRect) {
        if let background {
            NSColor.theme(background).setFill()
            bounds.fill()
        }
        if focused {
            NSColor.theme(.accent).setFill()
            NSRect(x: 0, y: 0, width: EditorMetrics.focusBarWidth, height: bounds.height).fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

/// Line number + code. Markers rows (base / separator / end) reuse it with a label instead of code.
final class LineCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("line")

    private let number = NSTextField(labelWithString: "")
    private let code = NSTextField(labelWithString: "")
    private var gutterWidth: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        number.font = EditorMetrics.gutterFont
        number.alignment = .right
        number.textColor = .theme(.textSubtle)
        code.font = EditorMetrics.codeFont
        code.lineBreakMode = .byClipping
        code.cell?.usesSingleLineMode = true
        for view in [number, code] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        gutterWidth = number.widthAnchor.constraint(equalToConstant: 40)
        NSLayoutConstraint.activate([
            number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: EditorMetrics.focusBarWidth + 2),
            gutterWidth,
            number.centerYAnchor.constraint(equalTo: centerYAnchor),
            code.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: EditorMetrics.gutterPadding),
            code.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            code.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(line: Int, gutter: CGFloat, text: NSAttributedString) {
        gutterWidth.constant = gutter
        number.stringValue = "\(line)"
        code.attributedStringValue = text
    }
}

/// The "<<<<<<<" row: who the current side is, and the actions (or the resolution and an undo).
final class ConflictHeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("header")

    enum Action: Int {
        case current, incoming, both, base, compare, undo
    }

    var onAction: ((Int, Action) -> Void)?
    private var conflict = 0
    private let title = NSTextField(labelWithString: "")
    private let buttons = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        title.font = EditorMetrics.headerFont
        title.textColor = .theme(.text)
        buttons.orientation = .horizontal
        buttons.spacing = 2
        for view in [title, buttons] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: EditorMetrics.focusBarWidth + 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttons.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(conflict: Int, choice: LFChoice, currentLabel: String, hasBase: Bool) {
        self.conflict = conflict
        let side = currentLabel.isEmpty ? "Current" : "Current (\(currentLabel))"
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if choice == .unresolved {
            title.stringValue = "◀ \(side)"
            var actions: [(String, Action)] = [("Accept Current", .current), ("Accept Incoming", .incoming), ("Accept Both", .both)]
            if hasBase { actions.append(("Accept Base", .base)) }
            actions.append(("Compare", .compare))
            for (index, action) in actions.enumerated() {
                if index > 0 { buttons.addArrangedSubview(separator()) }
                buttons.addArrangedSubview(link(action.0, action.1))
            }
        } else {
            title.stringValue = "✓ \(Self.describe(choice))"
            buttons.addArrangedSubview(link("Undo", .undo))
            buttons.addArrangedSubview(separator())
            buttons.addArrangedSubview(link("Compare", .compare))
        }
    }

    static func describe(_ choice: LFChoice) -> String {
        switch choice {
        case .current: "Accepted current"
        case .incoming: "Accepted incoming"
        case .bothCurrentFirst: "Accepted both (current first)"
        case .bothIncomingFirst: "Accepted both (incoming first)"
        case .base: "Restored base"
        case .custom: "Edited"
        case .unresolved: "Unresolved"
        }
    }

    private func link(_ title: String, _ action: Action) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(tapped(_:)))
        button.isBordered = false
        button.tag = action.rawValue
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = .theme(.accentText)
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.theme(.accentText), .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        ])
        button.setAccessibilityIdentifier("\(title.lowercased().replacingOccurrences(of: " ", with: "-"))-\(conflict)")
        return button
    }

    private func separator() -> NSTextField {
        let label = NSTextField(labelWithString: "·")
        label.textColor = .theme(.textSubtle)
        return label
    }

    @objc private func tapped(_ sender: NSButton) {
        if let action = Action(rawValue: sender.tag) {
            onAction?(conflict, action)
        }
    }
}
