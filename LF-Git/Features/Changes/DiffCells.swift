import AppKit
import LFKit

/// Optional blame (who last changed the line), old and new line numbers, then the diff line.
final class DiffLineCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("diff-line")
    /// Room for "a1b2c3d Author Name" before the line numbers.
    static let blameWidth: CGFloat = 190

    private let blameLabel = NSTextField(labelWithString: "")
    private var blameWidthConstraint: NSLayoutConstraint!
    private let oldNumber = NSTextField(labelWithString: "")
    private let newNumber = NSTextField(labelWithString: "")
    private let code = NSTextField(labelWithString: "")
    private var oldWidth: NSLayoutConstraint!
    private var newWidth: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        for label in [oldNumber, newNumber] {
            label.font = EditorMetrics.gutterFont
            label.alignment = .right
            label.textColor = .theme(.textSubtle)
        }
        blameLabel.font = EditorMetrics.gutterFont
        blameLabel.textColor = .theme(.textSubtle)
        blameLabel.lineBreakMode = .byTruncatingTail
        blameLabel.cell?.usesSingleLineMode = true
        code.font = EditorMetrics.codeFont
        code.lineBreakMode = .byClipping
        code.cell?.usesSingleLineMode = true
        for view in [blameLabel, oldNumber, newNumber, code] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        oldWidth = oldNumber.widthAnchor.constraint(equalToConstant: 40)
        newWidth = newNumber.widthAnchor.constraint(equalToConstant: 40)
        blameWidthConstraint = blameLabel.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            blameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            blameWidthConstraint,
            blameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            oldNumber.leadingAnchor.constraint(equalTo: blameLabel.trailingAnchor, constant: 6),
            oldWidth,
            newNumber.leadingAnchor.constraint(equalTo: oldNumber.trailingAnchor, constant: 6),
            newWidth,
            code.leadingAnchor.constraint(equalTo: newNumber.trailingAnchor, constant: EditorMetrics.gutterPadding),
            code.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            oldNumber.centerYAnchor.constraint(equalTo: centerYAnchor),
            newNumber.centerYAnchor.constraint(equalTo: centerYAnchor),
            code.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// - Parameter blame: the text of the blame column, or nil when the diff has no blame column at all.
    func configure(old: Int, new: Int, gutter: CGFloat, text: NSAttributedString, blame: String? = nil, blameTip: String? = nil) {
        blameWidthConstraint.constant = blame == nil ? 0 : Self.blameWidth
        blameLabel.stringValue = blame ?? ""
        blameLabel.toolTip = blameTip
        oldWidth.constant = gutter
        newWidth.constant = gutter
        oldNumber.stringValue = old > 0 ? "\(old)" : ""
        newNumber.stringValue = new > 0 ? "\(new)" : ""
        code.attributedStringValue = text
    }
}

/// The `@@ … @@` row, with the stage / unstage action for the hunk.
final class DiffHunkCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("diff-hunk")

    var onAction: (() -> Void)?
    private let title = NSTextField(labelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        title.font = EditorMetrics.gutterFont
        title.textColor = .theme(.accentText)
        title.lineBreakMode = .byTruncatingTail
        button.bezelStyle = .inline
        button.target = self
        button.action = #selector(tapped)
        for view in [title, button] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            button.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(hunk: DiffHunk, actionTitle: String?, identifier: String) {
        title.stringValue = hunk.title
        button.isHidden = actionTitle == nil
        button.attributedTitle = NSAttributedString(string: actionTitle ?? "", attributes: [
            .foregroundColor: NSColor.theme(.accentText), .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        ])
        button.setAccessibilityIdentifier(identifier)
    }

    @objc private func tapped() {
        onAction?()
    }
}
