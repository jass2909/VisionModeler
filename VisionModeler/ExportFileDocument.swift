import SwiftUI
import UniformTypeIdentifiers

struct ExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.usdz] }

    var fileURL: URL?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        self.fileURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = fileURL else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try FileWrapper(url: url, options: .immediate)
    }
}
