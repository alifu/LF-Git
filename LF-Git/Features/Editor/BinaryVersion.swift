import AppKit
import PDFKit
import UniformTypeIdentifiers

/// One side of a conflicted binary file, as read from the index.
nonisolated struct BinaryVersion: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// This side deleted the file.
        case missing
        case image
        case pdf
        case other
    }

    let data: Data?
    let kind: Kind

    var byteCount: Int { data?.count ?? 0 }

    static let missing = BinaryVersion(data: nil, kind: .missing)

    /// Decides how to preview `data`: by content first (PDF header, a decodable image), so a wrong extension does not matter.
    static func classify(_ data: Data?) -> BinaryVersion {
        guard let data else { return .missing }
        if data.starts(with: Array("%PDF".utf8)) { return BinaryVersion(data: data, kind: .pdf) }
        if NSImage(data: data) != nil { return BinaryVersion(data: data, kind: .image) }
        return BinaryVersion(data: data, kind: .other)
    }

    var image: NSImage? { kind == .image ? data.flatMap { NSImage(data: $0) } : nil }
    var document: PDFDocument? { kind == .pdf ? data.flatMap { PDFDocument(data: $0) } : nil }

    var sizeText: String {
        kind == .missing ? "deleted" : ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// "1200 × 800 px · 84 KB" for an image, "12 pages · 1.2 MB" for a PDF.
    var summary: String {
        switch kind {
        case .missing: return "This side deleted the file"
        case .image:
            guard let rep = image?.representations.first else { return sizeText }
            return "\(rep.pixelsWide) × \(rep.pixelsHigh) px · \(sizeText)"
        case .pdf:
            let pages = document?.pageCount ?? 0
            return "\(pages) page\(pages == 1 ? "" : "s") · \(sizeText)"
        case .other: return sizeText
        }
    }
}
