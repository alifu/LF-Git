/// What one line of a conflicted file is, for drawing it.
nonisolated enum LineRole: Equatable, Sendable {
    case plain
    case header(conflict: Int)     /* <<<<<<< */
    case current(conflict: Int)
    case baseHeader(conflict: Int) /* ||||||| */
    case base(conflict: Int)
    case separator(conflict: Int)  /* ======= */
    case incoming(conflict: Int)
    case footer(conflict: Int)     /* >>>>>>> */

    var conflict: Int? {
        switch self {
        case .plain: nil
        case .header(let c), .current(let c), .baseHeader(let c), .base(let c), .separator(let c), .incoming(let c),
             .footer(let c): c
        }
    }
}

/// Marker lines of one conflict (1-based; `baseLine` is 0 when there is no diff3 base section).
nonisolated struct ConflictSpan: Equatable, Sendable {
    let index: Int
    let openLine: Int
    let baseLine: Int
    let separatorLine: Int
    let closeLine: Int
}

/// Maps a line number to its role with a binary search over the conflicts, so a row of a
/// multi-million-line file is classified in O(log conflicts) without any per-line model.
nonisolated struct LineClassifier: Sendable {
    let spans: [ConflictSpan]

    func conflict(containingLine line: Int) -> Int? {
        var low = 0, high = spans.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let span = spans[middle]
            if line < span.openLine {
                high = middle - 1
            } else if line > span.closeLine {
                low = middle + 1
            } else {
                return middle
            }
        }
        return nil
    }

    func role(ofLine line: Int) -> LineRole {
        guard let index = conflict(containingLine: line) else { return .plain }
        let span = spans[index]
        switch line {
        case span.openLine: return .header(conflict: index)
        case span.closeLine: return .footer(conflict: index)
        case span.separatorLine: return .separator(conflict: index)
        case span.baseLine where span.baseLine > 0: return .baseHeader(conflict: index)
        default: break
        }
        if line > span.separatorLine {
            return .incoming(conflict: index)
        }
        if span.baseLine > 0 && line > span.baseLine {
            return .base(conflict: index)
        }
        return .current(conflict: index)
    }
}
