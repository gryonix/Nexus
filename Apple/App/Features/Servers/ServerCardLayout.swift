import CoreGraphics
import Foundation
import SwiftUI
import ServerControl

/// How the fleet is laid out into rows
enum ServerCardLayout {
    static func size(of deployment: Deployment, whenUnset fallback: ServerCardSize) -> ServerCardSize {
        deployment.cardSize ?? fallback
    }

    static func cellWidth(of deployment: Deployment,
                          listWidth: CGFloat?,
                          inset: CGFloat,
                          gutter: CGFloat,
                          whenUnset fallback: ServerCardSize) -> CGFloat? {
        guard let listWidth, listWidth.isFinite else { return nil }
        let full = listWidth - inset * 2
        guard full > 0 else { return nil }
        guard size(of: deployment, whenUnset: fallback) == .compact else { return full }
        return max(0, (full - gutter) / 2)
    }

    static func slots(of deployment: Deployment) -> Int {
        max(deployment.nodes.count, 1)
    }

    struct Row: Identifiable {
        var columns: [[Deployment]]

        /// Every card in the row, in drawing order
        var all: [Deployment] { columns.flatMap { $0 } }

        var id: UUID { columns.first?.first?.id ?? UUID() }
    }

    static func rows(of deployments: [Deployment],
                     whenUnset fallback: ServerCardSize) -> [Row] {
        var rows: [Row] = []
        var open: (index: Int, loads: [Int], budget: Int)?

        func closeIfFull() {
            guard let current = open else { return }
            // Full means no column can take even the shortest card.
            if current.loads.count == 2, current.loads.allSatisfy({ $0 >= current.budget }) {
                open = nil
            }
        }

        for deployment in deployments {
            guard size(of: deployment, whenUnset: fallback) == .compact else {
                rows.append(Row(columns: [[deployment]]))
                continue
            }
            let cost = slots(of: deployment)
            if var current = open {
                let order = current.loads.indices.sorted { current.loads[$0] < current.loads[$1] }
                if let column = order.first(where: { current.loads[$0] + cost <= current.budget }) {
                    rows[current.index].columns[column].append(deployment)
                    current.loads[column] += cost
                    open = current
                    closeIfFull()
                    continue
                }
                if current.loads.count < 2 {
                    rows[current.index].columns.append([deployment])
                    current.loads.append(cost)
                    current.budget = max(current.budget, cost)
                    open = current
                    closeIfFull()
                    continue
                }
            }
            rows.append(Row(columns: [[deployment]]))
            open = (index: rows.count - 1, loads: [cost], budget: cost)
        }
        return rows
    }
}
