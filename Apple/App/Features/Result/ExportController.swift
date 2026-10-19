import Foundation
import gryonixNexusCore

enum ExportController {
    static func exportURL(for artifact: Artifact) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gryonixNexusExport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(artifact.fileName)
        try artifact.contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
