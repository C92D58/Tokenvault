import Foundation

/// Import/Export helpers for .env, CSV, JSON formats.
enum ImportExportHelper {
    /// Parse .env format: KEY=VALUE
    static func parseEnv(_ content: String) -> [(name: String, value: String, note: String)] {
        content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0.contains("=") }
            .compactMap { line in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0].trimmingCharacters(in: .whitespaces),
                        parts[1].trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "\"", with: "")
                            .replacingOccurrences(of: "'", with: ""),
                        L("從 .env 匯入"))
            }
    }

    /// Parse CSV: name,value,note,environment
    static func parseCSV(_ content: String) -> [(name: String, value: String, note: String, env: TokenEnvironment)] {
        content.components(separatedBy: .newlines)
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 2 else { return nil }
                let env = parts.count >= 4 ? TokenEnvironment(rawValue: parts[3]) ?? .production : .production
                return (parts[0], parts[1], parts.count >= 3 ? parts[2] : "", env)
            }
    }

    /// Export as .env
    static func exportEnv(_ tokens: [TokenItem]) -> String {
        tokens.map { "\($0.name.sanitizedForEnv)=\($0.decryptedValue())" }.joined(separator: "\n")
    }

    /// Export as CSV
    static func exportCSV(_ tokens: [TokenItem]) -> String {
        var csv = "名稱,值,備註,環境,類型,到期日\n"
        for t in tokens {
            csv += "\"\(t.name)\",\"\(t.decryptedValue())\",\"\(t.note)\",\(t.environment.rawValue),\(t.provider.label),\(t.expiresAt?.ISO8601Format() ?? "")\n"
        }
        return csv
    }
}

extension String {
    var sanitizedForEnv: String {
        replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .uppercased()
    }
}
