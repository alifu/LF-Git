import AppKit
import SwiftUI

/// The rounded outline every top-bar control sits in. Drawn entirely by us with theme tokens, so it never picks up the
/// system's Liquid Glass bezel (macOS 26), unlike `.bordered` / `.borderedProminent` and the default push button.
private struct PillChrome: ViewModifier {
    let isProminent: Bool
    let isPressed: Bool
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    /// How much a disabled control fades.
    private static let disabledOpacity = 0.45

    func body(content: Content) -> some View {
        content
            .font(.callout)
            .foregroundStyle(.theme(isProminent ? .onAccent : .text))
            .padding(.horizontal, 10)
            .frame(height: Chrome.pillHeight)
            .background(RoundedRectangle(cornerRadius: Chrome.pillRadius).fill(fill))
            .overlay {
                if !isProminent {
                    RoundedRectangle(cornerRadius: Chrome.pillRadius).strokeBorder(.theme(.border))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Chrome.pillRadius))
            .opacity(isEnabled ? 1 : Self.disabledOpacity)
            .onHover { isHovering = $0 }
    }

    private var fill: Color {
        guard isEnabled else { return isProminent ? .theme(.accent) : .clear }
        if isProminent { return .theme(isPressed || isHovering ? .accentHover : .accent) }
        if isPressed { return .theme(.border) }
        return isHovering ? .theme(.surfaceRaised) : .clear
    }
}

/// An outlined pill button; `prominent` fills it with the accent, for the one thing worth doing now.
struct PillButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .modifier(PillChrome(isProminent: isProminent, isPressed: configuration.isPressed))
    }
}

/// The app-wide button: the pill look without forcing title and icon, so an icon-only or text-only label stays as
/// it is. Set as the default style of every window (`LF_GitApp`), it replaces the system push button and its Liquid
/// Glass bezel; buttons with a style of their own (`.borderless`, `.link`, `.plain`) are not affected.
struct FlatButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PillChrome(isProminent: isProminent, isPressed: configuration.isPressed))
    }
}

extension ButtonStyle where Self == FlatButtonStyle {
    static var flat: FlatButtonStyle { FlatButtonStyle() }
    /// For the default action of a sheet or bar (Save, Clone, Done).
    static var flatProminent: FlatButtonStyle { FlatButtonStyle(isProminent: true) }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var prominentPill: PillButtonStyle { PillButtonStyle(isProminent: true) }
}

extension ToolbarContent {
    /// macOS 26 puts every toolbar item on a shared Liquid Glass capsule; our pills draw their own outline, so the
    /// capsule is hidden. Earlier systems have no glass and need nothing.
    @ToolbarContentBuilder
    func withoutGlass() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension View {
    /// Puts a menu (or any label) in the pill outline.
    func pillChrome() -> some View {
        modifier(PillChrome(isProminent: false, isPressed: false))
    }
}

/// Pills joined into one outline, like "remote │ last fetch". Put a `PillDivider` between the segments.
struct PillGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .buttonStyle(PlainSegmentStyle())
            .menuStyle(.borderlessButton)
            .frame(height: Chrome.pillHeight)
            .clipShape(RoundedRectangle(cornerRadius: Chrome.pillRadius))
            .overlay(RoundedRectangle(cornerRadius: Chrome.pillRadius).strokeBorder(.theme(.border)))
    }
}

/// The hairline between two segments of a `PillGroup`.
struct PillDivider: View {
    var body: some View {
        Rectangle().fill(.theme(.border)).frame(width: 1, height: 14).accessibilityHidden(true)
    }
}

/// One segment of a `PillGroup`: no outline of its own, a soft fill while hovered or pressed.
private struct PlainSegmentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SegmentBody(configuration: configuration)
    }

    private struct SegmentBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .foregroundStyle(.theme(.text))
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .background(configuration.isPressed ? Color.theme(.border) : (isHovering ? .theme(.surfaceRaised) : .clear))
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}

/// Lets the custom top bar move the window like a title bar: drag to move, double-click to zoom.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

#if DEBUG
#Preview("Pills") {
    HStack(spacing: 8) {
        PillGroup {
            Button {} label: { Label("origin/main", systemImage: "antenna.radiowaves.left.and.right") }
            PillDivider()
            Button {} label: { Label("1 min ago", systemImage: "arrow.triangle.2.circlepath") }
        }
        Button("3 upstream commits") {}.buttonStyle(.prominentPill)
        Button {} label: { Label("New branch", systemImage: "plus") }.buttonStyle(.pill)
    }
    .padding()
    .background(.theme(.surfaceSunken))
}
#endif
