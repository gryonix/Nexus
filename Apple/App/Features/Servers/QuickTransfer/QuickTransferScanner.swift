import AVFoundation
import CoreImage
import SwiftUI

/// Runs the camera and reports every QR code it sees
final class QuickTransferCamera: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "quicktransfer.camera")
    var onCode: (String) -> Void = { _ in }

    /// False when there is no camera or no permission
    func start() async -> Bool {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: configure())
            }
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []
        session.commitConfiguration()
        session.startRunning()
        return true
    }

    func stop() {
        queue.async { [session] in session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for case let code as AVMetadataMachineReadableCodeObject in metadataObjects {
            if let text = code.stringValue { onCode(text) }
        }
    }

    /// Reads a QR code out of a picture
    static func code(inImage data: Data) -> String? {
        guard let image = CIImage(data: data),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}

#if os(macOS)
/// The live camera picture
struct QuickTransferCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#else
/// The live camera picture
struct QuickTransferCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        if let layer = view.layer as? AVCaptureVideoPreviewLayer {
            layer.session = session
            layer.videoGravity = .resizeAspectFill
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
#endif

struct QuickTransferScannerView: View {
    var imageProblemText: LocalizedStringKey = "That image holds no transfer code."
    let onCode: (String) -> Bool

    @State private var camera = QuickTransferCamera()
    @State private var cameraReady: Bool?
    @State private var choosingImage = false
    @State private var imageProblem = false

    var body: some View {
        VStack(spacing: 16) {
            viewfinder
            Button {
                choosingImage = true
            } label: {
                Label("Choose an image of the code", systemImage: "photo")
            }
            .buttonStyle(.borderless)
            if imageProblem {
                Text(imageProblemText).font(.callout).foregroundStyle(.red)
            }
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { read($0) }
        .task { await startCamera() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.black.opacity(0.85))
            if cameraReady == true {
                QuickTransferCameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                QuickTransferViewfinderFrame()
            } else if cameraReady == false {
                Label("The camera is not available.", systemImage: "camera.metering.unknown")
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 360)
    }

    private func startCamera() async {
        camera.onCode = { text in
            if onCode(text) { camera.stop() }
        }
        cameraReady = await camera.start()
    }

    private func read(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let text = (try? Data(contentsOf: url)).flatMap(QuickTransferCamera.code(inImage:))
        imageProblem = !(text.map(onCode) ?? false)
        if !imageProblem { camera.stop() }
    }
}

/// Four corners that breathe while scanning
struct QuickTransferViewfinderFrame: View {
    @State private var breathing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [36, 1000]))
            .foregroundStyle(.white)
            .padding(36)
            .scaleEffect(breathing ? 1.03 : 0.97)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: breathing)
            .onAppear { breathing = true }
            .accessibilityHidden(true)
    }
}
