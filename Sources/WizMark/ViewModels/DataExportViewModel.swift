import Foundation
import os

// MARK: - ExportFormat

/// Supported export file formats.
enum ExportFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case csv = "CSV"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        }
    }

    var mimeType: String {
        switch self {
        case .json: "application/json"
        case .csv: "text/csv"
        }
    }
}

// MARK: - DataExportViewModel

/// Drives the data export screen: format selection, export generation, and file sharing.
@Observable
@MainActor
final class DataExportViewModel {

    // MARK: - State

    var selectedFormat: ExportFormat = .json
    private(set) var isExporting: Bool = false
    private(set) var exportedFileURL: URL?
    var showShareSheet: Bool = false
    var showError: Bool = false
    private(set) var error: Error?

    // MARK: - Private

    private let userService: UserService
    private let bookmarkService: BookmarkService
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "DataExport")

    // MARK: - Init

    init(userService: UserService, bookmarkService: BookmarkService) {
        self.userService = userService
        self.bookmarkService = bookmarkService
    }

    // MARK: - Export

    /// Generate the export file and prepare it for sharing.
    func exportData() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let data = try await userService.exportUserData()
            let dateString = ISO8601DateFormatter().string(from: .now).prefix(10)
            let filename = "wizmark-export-\(dateString).\(selectedFormat.fileExtension)"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            switch selectedFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(data)
                try jsonData.write(to: tempURL)

            case .csv:
                let csv = convertToCSV(data)
                try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            }

            exportedFileURL = tempURL
            showShareSheet = true
            logger.info("Data exported as \(self.selectedFormat.rawValue, privacy: .public)")
        } catch {
            self.error = error
            showError = true
            logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - CSV Conversion

    /// Convert the exported data into a CSV string.
    /// Exports bookmarks as the primary table since that is the main user data.
    private func convertToCSV(_ data: UserDataExport) -> String {
        var lines: [String] = []

        // Header
        lines.append("type,email,displayName,username,category,message,appVersion,platform,exportedAt")

        // User row
        if let user = data.user {
            let row = [
                "user",
                escapeCSV(user.email),
                escapeCSV(user.displayName ?? ""),
                escapeCSV(user.username ?? ""),
                "", "", "", "",
                escapeCSV(data.exportedAt),
            ]
            lines.append(row.joined(separator: ","))
        }

        // Feedback rows
        for fb in data.feedback {
            let row = [
                "feedback",
                "", "", "",
                escapeCSV(fb.category),
                escapeCSV(fb.message),
                escapeCSV(fb.appVersion ?? ""),
                escapeCSV(fb.platform ?? ""),
                escapeCSV(fb.submittedAt),
            ]
            lines.append(row.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    /// Escape a CSV field value, wrapping in quotes if needed.
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
