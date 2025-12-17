import Foundation
import PDFKit

enum PDFTextExtractor {
    static let extractorVersion: Int = 1
    private static let cacheFormatVersion: Int = 1

    static func extractPages(from url: URL) throws -> [String] {
        guard let document = PDFDocument(url: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var pages: [String] = Array(repeating: "", count: document.pageCount)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pages[index] = normalizeExtractedText(page.string ?? "")
        }
        return pages
    }

    static func extractPages(from url: URL, cacheID: UUID) throws -> [String] {
        if let cached = loadCachedPages(for: cacheID, pdfURL: url) {
            return cached
        }

        let pages = try extractPages(from: url)
        saveCachedPages(pages, for: cacheID, pdfURL: url)
        return pages
    }

    static func extractText(from url: URL) throws -> String {
        let pages = try extractPages(from: url)
        return pages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func normalizeExtractedText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{00AD}", with: "")

        let rawLines = normalized.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        var paragraphs: [[String]] = []
        var currentParagraph: [String] = []

        for rawLine in rawLines {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !currentParagraph.isEmpty {
                    paragraphs.append(currentParagraph)
                    currentParagraph = []
                }
                continue
            }
            currentParagraph.append(line)
        }
        if !currentParagraph.isEmpty {
            paragraphs.append(currentParagraph)
        }

        let reflowedParagraphs = paragraphs.map { reflowParagraph($0) }
        normalized = reflowedParagraphs
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
    }

    private static func reflowParagraph(_ lines: [String]) -> String {
        let trimmedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedLines.isEmpty else { return "" }
        guard trimmedLines.count > 1 else { return trimmedLines[0] }

        if shouldPreserveLineBreaks(trimmedLines) {
            return trimmedLines.joined(separator: "\n")
        }

        var result = trimmedLines[0]
        for next in trimmedLines.dropFirst() {
            if result.hasSuffix("-"), next.first?.isLowercase == true {
                result.removeLast()
                result += next
                continue
            }

            if result.last?.isWhitespace == false {
                result += " "
            }
            result += next
        }
        return result
    }

    private static func shouldPreserveLineBreaks(_ lines: [String]) -> Bool {
        let bulletPrefixes: [String] = ["•", "‣", "◦", "⁃", "-", "–", "—", "*", "·"]
        let bulletLikeCount = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if bulletPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }

            let scalars = Array(trimmed.unicodeScalars)
            var index = 0
            while index < scalars.count, CharacterSet.decimalDigits.contains(scalars[index]) {
                index += 1
            }
            guard index > 0 else { return false }
            if index < scalars.count, (scalars[index] == "." || scalars[index] == ")") {
                return true
            }
            return false
        }.count

        return bulletLikeCount >= 2 && bulletLikeCount * 2 >= lines.count
    }

    static func removeCachedPages(for cacheID: UUID) {
        do {
            let cacheURL = try cacheFileURL(for: cacheID)
            guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
            try FileManager.default.removeItem(at: cacheURL)
        } catch {
            return
        }
    }

    private struct CachedPages: Codable {
        let formatVersion: Int
        let extractorVersion: Int
        let fileSize: Int?
        let modificationDate: Date?
        let pages: [String]
    }

    private static func loadCachedPages(for cacheID: UUID, pdfURL: URL) -> [String]? {
        do {
            let cacheURL = try cacheFileURL(for: cacheID)
            guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }

            let data = try Data(contentsOf: cacheURL)
            let cached = try JSONDecoder().decode(CachedPages.self, from: data)

            guard cached.formatVersion == cacheFormatVersion else { return nil }
            guard cached.extractorVersion == extractorVersion else { return nil }

            let fileInfo = pdfFileInfo(for: pdfURL)
            if let cachedSize = cached.fileSize, let currentSize = fileInfo.fileSize, cachedSize != currentSize {
                return nil
            }
            if let cachedDate = cached.modificationDate, let currentDate = fileInfo.modificationDate,
               abs(cachedDate.timeIntervalSince(currentDate)) > 1 {
                return nil
            }

            return cached.pages
        } catch {
            do {
                let cacheURL = try cacheFileURL(for: cacheID)
                try? FileManager.default.removeItem(at: cacheURL)
            } catch {
                return nil
            }
            return nil
        }
    }

    private static func saveCachedPages(_ pages: [String], for cacheID: UUID, pdfURL: URL) {
        do {
            let fileInfo = pdfFileInfo(for: pdfURL)
            let cached = CachedPages(
                formatVersion: cacheFormatVersion,
                extractorVersion: extractorVersion,
                fileSize: fileInfo.fileSize,
                modificationDate: fileInfo.modificationDate,
                pages: pages
            )

            let cacheURL = try cacheFileURL(for: cacheID)
            let data = try JSONEncoder().encode(cached)
            try data.write(to: cacheURL, options: [.atomic])
        } catch {
            return
        }
    }

    private static func pdfFileInfo(for url: URL) -> (fileSize: Int?, modificationDate: Date?) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (values?.fileSize, values?.contentModificationDate)
    }

    private static func cacheFileURL(for cacheID: UUID) throws -> URL {
        let dir = try cacheDirectory()
        return dir.appendingPathComponent(cacheID.uuidString).appendingPathExtension("json")
    }

    private static func cacheDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let dir = cachesDir
            .appendingPathComponent("LoveRead", isDirectory: true)
            .appendingPathComponent("ExtractedPDFText", isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
