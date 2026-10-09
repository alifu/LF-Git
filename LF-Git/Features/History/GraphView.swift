import LFKit
import SwiftUI

/// The lanes of one history row: lines through the row, joins, branches and the commit's dot.
struct GraphRowView: View {
    let row: CommitGraph.Row
    let isMerge: Bool

    static let laneWidth: CGFloat = 14
    private static let dotRadius: CGFloat = 4
    private static let lineWidth: CGFloat = 1.6
    private static let laneColors: [LFThemeToken] = [.accent, .info, .warning, .syntaxKeyword, .minimapCurrent, .danger]

    private func x(_ lane: Int) -> CGFloat {
        CGFloat(lane) * Self.laneWidth + Self.laneWidth / 2
    }

    var body: some View {
        // Read here, on the main actor: the Canvas closure may run elsewhere.
        let palette = Self.laneColors.map { Color.theme($0) }
        let strokeWidth = Self.lineWidth
        return Canvas { context, size in
            let middle = size.height / 2
            func line(from: CGPoint, to: CGPoint, lane: Int) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(palette[lane % palette.count]), lineWidth: strokeWidth)
            }
            for lane in row.passingLanes {
                line(from: CGPoint(x: x(lane), y: 0), to: CGPoint(x: x(lane), y: size.height), lane: lane)
            }
            if row.hasLineAbove {
                line(from: CGPoint(x: x(row.lane), y: 0), to: CGPoint(x: x(row.lane), y: middle), lane: row.lane)
            }
            if row.continuesDown {
                line(from: CGPoint(x: x(row.lane), y: middle), to: CGPoint(x: x(row.lane), y: size.height), lane: row.lane)
            }
            for lane in row.mergedLanes { // a side branch ends here: its line slopes into the dot from above
                line(from: CGPoint(x: x(lane), y: 0), to: CGPoint(x: x(row.lane), y: middle), lane: lane)
            }
            for lane in row.branchedLanes { // a merge: a line leaves towards the other parent
                line(from: CGPoint(x: x(row.lane), y: middle), to: CGPoint(x: x(lane), y: size.height), lane: lane)
            }
            let center = CGPoint(x: x(row.lane), y: middle)
            let radius = Self.dotRadius
            let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(palette[row.lane % palette.count]))
            if isMerge {
                context.stroke(dot, with: .color(.theme(.background)), lineWidth: 1.5)
            }
        }
        .frame(width: CGFloat(max(row.laneCount, 1)) * Self.laneWidth)
        .accessibilityHidden(true)
    }
}
