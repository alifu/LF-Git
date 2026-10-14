import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A preview of one version: the image, a scrollable PDF, or the file's icon.
struct BinaryPreview: View {
    let version: BinaryVersion
    let fileName: String

    var body: some View {
        switch version.kind {
        case .missing:
            placeholder(symbol: "trash", text: "Deleted on this side")
        case .image:
            if let image = version.image {
                Image(nsImage: image).resizable().scaledToFit().padding(4)
            }
        case .pdf:
            if let document = version.document { PDFPreview(document: document) }
        case .other:
            let type = UTType(filenameExtension: (fileName as NSString).pathExtension) ?? .data
            VStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(for: type)).resizable().scaledToFit().frame(width: 72, height: 72)
                Text("No preview for this file type").font(.caption).foregroundStyle(.theme(.textSubtle))
            }
        }
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle)
            Text(text).font(.caption)
        }
        .foregroundStyle(.theme(.textSubtle))
    }
}

/// A PDF the user can scroll, zoom, select and copy text from.
struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

/// Two images on top of each other: a slider moves the edge between them (left shows the current one).
struct ImageSwipeView: View {
    let current: NSImage
    let incoming: NSImage
    let fraction: Double

    var body: some View {
        ZStack {
            Image(nsImage: incoming).resizable().scaledToFit()
            Image(nsImage: current).resizable().scaledToFit()
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle().frame(width: proxy.size.width * fraction)
                    }
                }
        }
        .padding(4)
    }
}
