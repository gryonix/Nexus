import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum QuickTransferModules {
    static func grid(for text: String) -> [[Bool]] {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return [] }
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        CIContext().render(image, toBitmap: &pixels, rowBytes: width * 4, bounds: image.extent,
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let rows = (0..<height).map { y in (0..<width).map { x in pixels[(y * width + x) * 4] < 128 } }
        return trimmed(rows)
    }

    /// Drops the quiet border the generator adds
    static func trimmed(_ rows: [[Bool]]) -> [[Bool]] {
        let dark = rows.indices.filter { rows[$0].contains(true) }
        let columns = (0..<(rows.first?.count ?? 0)).filter { column in rows.contains { $0[column] } }
        guard let top = dark.first, let bottom = dark.last,
              let left = columns.first, let right = columns.last else { return [] }
        return rows[top...bottom].map { Array($0[left...right]) }
    }
}

/// A QR code that can scatter into flying dots
struct QuickTransferQRView: View {
    let modules: [[Bool]]
    let scatteredAt: Date?

    var body: some View {
        TimelineView(.animation(paused: scatteredAt == nil)) { context in
            Canvas { canvas, size in
                draw(in: &canvas, size: size, time: elapsed(at: context.date))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(scatteredAt == nil ? 1 : 0)))
        .animation(.easeOut(duration: 0.6), value: scatteredAt)
        .accessibilityLabel(Text("Transfer QR code"))
    }

    private func elapsed(at date: Date) -> Double {
        scatteredAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let count = modules.count
        guard count > 0 else { return }
        let cell = size.width / CGFloat(count + 4)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        for (row, line) in modules.enumerated() {
            for (column, isDark) in line.enumerated() where isDark {
                let origin = CGPoint(x: CGFloat(column + 2) * cell, y: CGFloat(row + 2) * cell)
                let seed = QuickTransferNoise.value(row, column)
                let progress = min(1, max(0, (time - seed * 0.35) / 0.75))
                drawModule(in: &canvas, origin: origin, cell: cell, centre: centre,
                           seed: seed, progress: progress, reach: size.width)
            }
        }
    }

    private func drawModule(in canvas: inout GraphicsContext, origin: CGPoint, cell: CGFloat, centre: CGPoint,
                            seed: Double, progress: Double, reach: CGFloat) {
        guard progress < 1 else { return }
        let dx = origin.x - centre.x
        let dy = origin.y - centre.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let push = reach * CGFloat(progress * progress) * CGFloat(0.6 + seed)
        let point = CGPoint(x: origin.x + dx / length * push - dy / length * push * 0.3,
                            y: origin.y + dy / length * push + dx / length * push * 0.3)
        let side = cell * CGFloat(1 - progress * 0.55)
        let rect = CGRect(x: point.x, y: point.y, width: side, height: side)
        let shape = progress > 0 ? Path(ellipseIn: rect) : Path(rect.insetBy(dx: -0.25, dy: -0.25))
        let colour: Color = progress > 0 ? .accentColor : .black
        canvas.fill(shape, with: .color(colour.opacity(1 - progress)))
    }
}

/// Repeatable pseudo-random numbers in 0..<1
enum QuickTransferNoise {
    static func value(_ a: Int, _ b: Int) -> Double {
        var hash = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663)
        hash = (hash ^ (hash >> 13)) &* 0x5bd1_e995
        return Double(hash % 1000) / 1000
    }
}

/// Dots running from one device to the other
struct QuickTransferDotsView: View {
    let from: String
    let to: String
    var dots = 6

    var body: some View {
        HStack(spacing: 0) {
            device(from)
            TimelineView(.animation) { context in
                Canvas { canvas, size in
                    drawDots(in: &canvas, size: size, time: context.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(height: 24)
            device(to)
        }
        .accessibilityHidden(true)
    }

    private func device(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 40, weight: .light))
            .foregroundStyle(.tint)
            .frame(width: 64)
    }

    private func drawDots(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<dots {
            let phase = (time * 0.7 + Double(index) / Double(dots)).truncatingRemainder(dividingBy: 1)
            let swell = sin(phase * .pi)
            let radius = 3 + 3 * swell
            let x = size.width * phase
            let y = size.height / 2 - CGFloat(sin(phase * .pi * 2)) * 4
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            canvas.fill(Path(ellipseIn: rect), with: .color(.accentColor.opacity(0.25 + 0.75 * swell)))
        }
    }
}

/// Dots gather into the arrived server cards
struct QuickTransferArrivalView: View {
    let names: [String]
    @State private var start = Date()
    @State private var landed = false

    var body: some View {
        ZStack {
            if !landed {
                TimelineView(.animation) { context in
                    Canvas { canvas, size in
                        gather(in: &canvas, size: size, progress: context.date.timeIntervalSince(start) / 0.8)
                    }
                }
            }
            if landed { cards.transition(.scale(scale: 0.6).combined(with: .opacity)) }
        }
        .frame(minHeight: 220)
        .sensoryFeedback(.success, trigger: landed)
        .task {
            start = Date()
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { landed = true }
        }
    }

    private var cards: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: landed)
            ForEach(Array(names.prefix(4).enumerated()), id: \.offset) { _, name in
                QuickTransferServerChip(name: name)
            }
            if names.count > 4 {
                Text(verbatim: "+\(names.count - 4)").foregroundStyle(.secondary)
            }
        }
    }

    private func gather(in canvas: inout GraphicsContext, size: CGSize, progress: Double) {
        let eased = 1 - pow(1 - min(1, max(0, progress)), 3)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        for index in 0..<48 {
            let angle = QuickTransferNoise.value(index, 7) * .pi * 2
            let distance = (0.5 + QuickTransferNoise.value(index, 3)) * Double(size.width) * 0.6 * (1 - eased)
            let point = CGPoint(x: centre.x + CGFloat(cos(angle) * distance),
                                y: centre.y + CGFloat(sin(angle) * distance))
            let rect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
            canvas.fill(Path(ellipseIn: rect), with: .color(.accentColor.opacity(0.3 + 0.7 * eased)))
        }
    }
}

/// One arrived server, as a small card
struct QuickTransferServerChip: View {
    let name: String

    var body: some View {
        Label {
            Text(verbatim: name).lineLimit(1)
        } icon: {
            Image(systemName: "server.rack").foregroundStyle(.tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// This device and the other one, as symbols
enum QuickTransferDevice {
    static var current: String {
        #if os(macOS)
        "laptopcomputer"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }
}
