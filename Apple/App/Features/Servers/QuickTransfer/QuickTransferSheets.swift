import ServerControl
import SwiftUI

/// Servers picked for one QR transfer
struct QuickTransferTarget: Identifiable {
    let id = UUID()
    let deployments: [Deployment]
}

/// The chooser, the sending sheet and the receiving sheet
struct QuickTransferSheets: ViewModifier {
    @ObservedObject var viewModel: ServerListViewModel
    @ObservedObject var transfer: ServerTransferModel
    @Binding var choosing: Bool
    @Binding var chosen: [Deployment]
    @Binding var sending: QuickTransferTarget?
    @Binding var receiving: Bool
    let send: ([Deployment]) async -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $choosing, onDismiss: sendChosen) {
                ServerMultiExportView(deployments: viewModel.deployments, onExport: { picked in
                    chosen = picked
                    choosing = false
                }, title: "Send by QR code", actionTitle: "Next")
            }
            .sheet(item: $sending) { target in
                QuickTransferSendView(model: QuickTransferSendModel(deployments: target.deployments) { deployment in
                    await viewModel.transferText(for: deployment)
                })
            }
            .sheet(isPresented: $receiving, onDismiss: { transfer.askNextReplacement() }) {
                QuickTransferReceiveView(model: QuickTransferReceiveModel { transfers in
                    transfer.offer(transfers, into: viewModel)
                })
            }
    }

    private func sendChosen() {
        let picked = chosen
        chosen = []
        Task { await send(picked) }
    }
}
