import CoreGraphics

/// Where a floating panel sits: an offset from the centre of the window's content, kept inside it. Pure, O(1).
nonisolated enum FloatingPlacement {
    /// Space kept between a panel and the edge of the content area.
    static let margin: CGFloat = 8

    /// `offset` limited so a panel of `panel` size stays inside `container`; a panel that does not fit stays centred.
    static func clamp(_ offset: CGSize, panel: CGSize, in container: CGSize) -> CGSize {
        CGSize(width: clamp(offset.width, limit: (container.width - panel.width) / 2),
               height: clamp(offset.height, limit: (container.height - panel.height) / 2))
    }

    /// `size`, shrunk to fit inside `container` with a margin on every side.
    static func fitted(_ size: CGSize, in container: CGSize) -> CGSize {
        CGSize(width: max(0, min(size.width, container.width - margin * 2)),
               height: max(0, min(size.height, container.height - margin * 2)))
    }

    private static func clamp(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        return min(max(value, -limit), limit)
    }
}
