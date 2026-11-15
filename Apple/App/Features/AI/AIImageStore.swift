import AIAssistant
import Foundation
import ServerControl
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// AI chat pictures stored as JPEG files
enum AIImageStore {
    static let maxSide: CGFloat = 1568

    private static var directory: URL {
        AppSupportDirectory.base.appendingPathComponent("gryonixNexus/ai-images", isDirectory: true)
    }

    private static func url(_ id: String) -> URL {
        directory.appendingPathComponent(id + ".jpg")
    }

    /// Saves a shrunk JPEG and returns its id
    static func save(_ jpeg: Data) -> String? {
        let id = UUID().uuidString
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: url(id), options: [.atomic, .completeFileProtection])
            return id
        } catch {
            return nil
        }
    }

    static func data(_ id: String) -> Data? { try? Data(contentsOf: url(id)) }

    static func delete(_ ids: [String]) {
        ids.forEach { try? FileManager.default.removeItem(at: url($0)) }
    }

    /// The pictures of one message, ready for the request
    static func wire(_ ids: [String]?) -> [AIImage] {
        (ids ?? []).compactMap { data($0) }
            .map { AIImage(mediaType: "image/jpeg", base64: $0.base64EncodedString()) }
    }

    /// Picture data as a JPEG within `maxSide`
    static func jpeg(from data: Data) -> Data? {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
        #elseif os(macOS)
        guard let rep = NSBitmapImageRep(data: data),
              let cgImage = rep.cgImage else { return nil }
        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        let scale = min(1, maxSide / max(width, height))
        let target = NSSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        let resized = NSImage(size: target)
        resized.lockFocus()
        NSImage(cgImage: cgImage, size: .zero).draw(in: NSRect(origin: .zero, size: target))
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation, let out = NSBitmapImageRep(data: tiff) else { return nil }
        return out.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #else
        return nil
        #endif
    }

    /// A SwiftUI image from stored or pending JPEG data
    static func image(_ data: Data) -> Image? {
        #if os(iOS)
        UIImage(data: data).map { Image(uiImage: $0) }
        #elseif os(macOS)
        NSImage(data: data).map { Image(nsImage: $0) }
        #else
        nil
        #endif
    }
}
