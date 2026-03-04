import Foundation

final class CorrectionEngine {
    private struct Token {
        let raw: String
        let lower: String
    }

    private struct ReplacementSegment {
        let sourceLower: [String]
        let targetRaw: [String]
    }

    struct Entry: Codable {
        var from: String
        var to: String
        var count: Int
        var updatedAt: Date
    }

    private struct Payload: Codable {
        var version: Int
        var entries: [Entry]
    }

    private let storageURL: URL
    private var entriesBySource: [String: Entry] = [:]

    init(storageURL: URL) {
        self.storageURL = storageURL
        load()
    }

    func correct(_ text: String) -> String {
        let source = normalizeWhitespace(text)
        guard !source.isEmpty, !entriesBySource.isEmpty else {
            return source
        }

        var result = source
        let entries = entriesBySource.values.sorted { lhs, rhs in
            let lWords = lhs.from.split(separator: " ").count
            let rWords = rhs.from.split(separator: " ").count
            if lWords != rWords {
                return lWords > rWords
            }
            return lhs.from.count > rhs.from.count
        }

        for entry in entries {
            result = replacePhrase(entry.from, with: entry.to, in: result)
        }
        return normalizeWhitespace(result)
    }

    @discardableResult
    func learn(fromOriginal original: String, corrected: String) -> Int {
        let source = normalizeWhitespace(original)
        let target = normalizeWhitespace(corrected)
        guard !source.isEmpty, !target.isEmpty else { return 0 }
        guard source.caseInsensitiveCompare(target) != .orderedSame else { return 0 }

        let sourceTokens = tokenize(source)
        let targetTokens = tokenize(target)
        guard !sourceTokens.isEmpty, !targetTokens.isEmpty else { return 0 }

        let segments = extractReplacementSegments(source: sourceTokens, target: targetTokens)
        var learned = 0

        for segment in segments {
            let fromPhrase = normalizeWhitespace(segment.sourceLower.joined(separator: " "))
            let toPhrase = normalizeWhitespace(segment.targetRaw.joined(separator: " "))
            if isValidMapping(from: fromPhrase, to: toPhrase) {
                upsert(from: fromPhrase, to: toPhrase)
                learned += 1
            }
        }

        if learned == 0 {
            // Explicit user correction fallback: learn full-phrase mapping.
            let fromPhrase = normalizeWhitespace(sourceTokens.map(\.lower).joined(separator: " "))
            let toPhrase = normalizeWhitespace(targetTokens.map(\.raw).joined(separator: " "))
            if isValidMapping(from: fromPhrase, to: toPhrase) {
                upsert(from: fromPhrase, to: toPhrase)
                learned = 1
            }
        }

        if learned > 0 {
            save()
        }
        return learned
    }

    private func tokenize(_ text: String) -> [Token] {
        let pattern = #"[[:alnum:]_\-\+]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.map { match in
            let raw = ns.substring(with: match.range)
            return Token(raw: raw, lower: raw.lowercased())
        }
    }

    private func extractReplacementSegments(source: [Token], target: [Token]) -> [ReplacementSegment] {
        let a = source.map(\.lower)
        let b = target.map(\.lower)
        let table = buildLCSTable(a, b)

        var i = 0
        var j = 0
        var result: [ReplacementSegment] = []

        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                i += 1
                j += 1
                continue
            }

            let startI = i
            let startJ = j

            while true {
                if i < a.count, j < b.count, a[i] == b[j] {
                    break
                }
                if i >= a.count, j >= b.count {
                    break
                }
                if i >= a.count {
                    j += 1
                    continue
                }
                if j >= b.count {
                    i += 1
                    continue
                }
                if table[i + 1][j] >= table[i][j + 1] {
                    i += 1
                } else {
                    j += 1
                }
            }

            if startI < i, startJ < j {
                result.append(
                    ReplacementSegment(
                        sourceLower: Array(a[startI..<i]),
                        targetRaw: Array(target[startJ..<j]).map(\.raw)
                    )
                )
            }
        }

        return result
    }

    private func buildLCSTable(_ a: [String], _ b: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        var i = a.count - 1
        while i >= 0 {
            var j = b.count - 1
            while j >= 0 {
                if a[i] == b[j] {
                    table[i][j] = table[i + 1][j + 1] + 1
                } else {
                    table[i][j] = max(table[i + 1][j], table[i][j + 1])
                }
                if j == 0 { break }
                j -= 1
            }
            if i == 0 { break }
            i -= 1
        }
        return table
    }

    private func isValidMapping(from: String, to: String) -> Bool {
        guard !from.isEmpty, !to.isEmpty else { return false }
        guard from != to.lowercased() else { return false }

        let fromWords = from.split(separator: " ").count
        let toWords = to.split(separator: " ").count
        guard (1...6).contains(fromWords), (1...8).contains(toWords) else { return false }
        guard from.count <= 48, to.count <= 64 else { return false }

        let lowerTo = to.lowercased()
        if from.contains("http") || lowerTo.contains("http") || from.contains("@") || lowerTo.contains("@") {
            return false
        }
        return true
    }

    private func upsert(from: String, to: String) {
        if var existing = entriesBySource[from] {
            existing.to = to
            existing.count += 1
            existing.updatedAt = Date()
            entriesBySource[from] = existing
        } else {
            entriesBySource[from] = Entry(from: from, to: to, count: 1, updatedAt: Date())
        }
    }

    private func replacePhrase(_ from: String, with to: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: from)
        let pattern = "(?i)(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: to)
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            entriesBySource = [:]
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(Payload.self, from: data)
            entriesBySource = Dictionary(uniqueKeysWithValues: payload.entries.map { ($0.from, $0) })
        } catch {
            entriesBySource = [:]
        }
    }

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let payload = Payload(version: 1, entries: Array(entriesBySource.values).sorted { $0.updatedAt > $1.updatedAt })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Keep dictation flow uninterrupted if persistence fails.
        }
    }
}
