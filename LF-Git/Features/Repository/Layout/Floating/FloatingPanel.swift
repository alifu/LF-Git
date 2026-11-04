import SwiftUI

/// A card that floats over the window's content (Figma "Floating diff" / "Floating window"): a ⠿ handle that drags it,
/// a title, a ✕ and a shadow. Place it in a full-size overlay; it centres itself, keeps inside `container`, and
/// remembers where it was dragged per window (`@SceneStorage`, keyed by `id`). Body: O(1) plus its content.
struct FloatingPanel<Content: View>: View {
    let title: String
    let size: CGSize
    let container: CGSize
    let identifier: String
    let onClose: () -> Void
    let content: Content
    @SceneStorage private var offsetX: Double
    @SceneStorage private var offsetY: Double
    @GestureState private var drag: CGSize = .zero

    private static var headerHeight: CGFloat { 36 }
    private static var shadowRadius: CGFloat { 18 }

    /// - Parameters:
    ///   - id: names the stored position; one per kind of panel.
    ///   - initialOffset: where the panel first appears, from the centre of the container.
    init(id: String, title: String, size: CGSize, container: CGSize, initialOffset: CGSize = .zero,
         onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.size = size
        self.container = container
        self.identifier = "floating-\(id)"
        self.onClose = onClose
        self.content = content()
        _offsetX = SceneStorage(wrappedValue: initialOffset.width, "floating.\(id).x")
        _offsetY = SceneStorage(wrappedValue: initialOffset.height, "floating.\(id).y")
    }

    private var fitted: CGSize { FloatingPlacement.fitted(size, in: container) }

    private var offset: CGSize {
        let moved = CGSize(width: offsetX + drag.width, height: offsetY + drag.height)
        return FloatingPlacement.clamp(moved, panel: fitted, in: container)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: fitted.width, height: fitted.height)
        .lfCard()
        .shadow(color: .theme(.text).opacity(0.18), radius: Self.shadowRadius, y: 6)
        .position(x: container.width / 2 + offset.width, y: container.height / 2 + offset.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.grid.2x3.fill")
                .font(.caption)
                .foregroundStyle(.theme(.textSubtle))
                .accessibilityLabel("Drag to move")
            Text(title).font(.body.weight(.medium)).foregroundStyle(.theme(.text)).lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Close \(title)")
                .accessibilityLabel("Close \(title)")
                .accessibilityIdentifier("\(identifier)-close")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.headerHeight)
        .background(.theme(.surfaceSunken))
        .overlay(alignment: .bottom) { Rectangle().fill(.theme(.border)).frame(height: 1) }
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let moved = CGSize(width: offsetX + value.translation.width, height: offsetY + value.translation.height)
                let kept = FloatingPlacement.clamp(moved, panel: fitted, in: container)
                offsetX = kept.width
                offsetY = kept.height
            }
    }
}
