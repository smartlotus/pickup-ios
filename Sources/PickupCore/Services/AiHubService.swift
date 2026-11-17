import Foundation

public enum AiProviderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case gemini
    case deepseek
    case glm
    case siliconflow
    case openai
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .deepseek: return "DeepSeek"
        case .glm: return "Zhipu GLM"
        case .siliconflow: return "SiliconFlow"
        case .openai: return "OpenAI"
        case .custom: return "Custom HTTPS"
        }
    }

    public var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .deepseek: return "deepseek-chat"
        case .glm: return "glm-4-plus"
        case .siliconflow: return "Pro/zai-org/GLM-4.7"
        case .openai: return "gpt-4.1-mini"
        case .custom: return "gpt-4.1-mini"
        }
    }

    public var defaultEndpointURL: String {
        switch self {
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .deepseek:
            return "https://api.deepseek.com/chat/completions"
        case .glm:
            return "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .siliconflow:
            return "https://api.siliconflow.cn/v1/chat/completions"
        case .openai:
            return "https://api.openai.com/v1/chat/completions"
        case .custom:
            return ""
        }
    }
}

public struct AiSettings: Codable, Sendable, Equatable {
    public var provider: AiProviderKind
    public var model: String
    public var customEndpointURL: String
    public var apiKey: String

    public init(
        provider: AiProviderKind = .deepseek,
        model: String = AiProviderKind.deepseek.defaultModel,
        customEndpointURL: String = "",
        apiKey: String = ""
    ) {
        self.provider = provider
        self.model = model
        self.customEndpointURL = customEndpointURL
        self.apiKey = apiKey
    }
}

public enum AiRecallScope: String, Codable, Sendable, CaseIterable {
    case intelligent
    case all
    case custom
}

public struct AiDisclosurePreview: Sendable, Equatable {
    public let providerName: String
    public let recordCount: Int
    public let characterCount: Int
    public let includedFields: [String]
    public let mediaBytesIncluded: Bool
    public let previewText: String
    public let dateStart: Date?
    public let dateEnd: Date?

    public init(
        providerName: String,
        recordCount: Int,
        characterCount: Int,
        includedFields: [String],
        mediaBytesIncluded: Bool,
        previewText: String,
        dateStart: Date?,
        dateEnd: Date?
    ) {
        self.providerName = providerName
        self.recordCount = recordCount
        self.characterCount = characterCount
        self.includedFields = includedFields
        self.mediaBytesIncluded = mediaBytesIncluded
        self.previewText = previewText
        self.dateStart = dateStart
        self.dateEnd = dateEnd
    }
}

public enum AiHubError: Error, Sendable, Equatable, LocalizedError {
    case missingApiKey
    case invalidEndpointURL
    case emptyContext
    case httpFailure(Int, String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Please configure an API Key for your chosen AI provider first."
        case .invalidEndpointURL:
            return "AI endpoint must be a valid HTTPS URL."
        case .emptyContext:
            return "No journal entries matched the selected scope."
        case .httpFailure(let code, let detail):
            return "AI request failed (HTTP \(code)): \(detail)"
        case .emptyResponse:
            return "AI returned an empty response."
        }
    }
}

public struct AiHubService: Sendable {
    public let repository: PickupRepository

    public init(repository: PickupRepository) {
        self.repository = repository
    }

    public func loadSettings() async -> AiSettings {
        guard let data = try? await repository.loadAiSettingsData(),
              let settings = try? JSONDecoder().decode(AiSettings.self, from: data) else {
            return AiSettings()
        }
        return settings
    }

    public func saveSettings(_ settings: AiSettings) async throws {
        let data = try JSONEncoder().encode(settings)
        try await repository.saveAiSettingsData(data)
    }

    public static func buildDisclosure(
        question: String,
        scope: AiRecallScope,
        customStart: Date?,
        customEnd: Date?,
        entries: [CapsuleEntry],
        providerName: String,
        maxCharacters: Int = 14_000,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AiDisclosurePreview {
        var resolvedRange: (Date, Date)? = nil
        var pool = entries.sorted { $0.timestamp > $1.timestamp }

        switch scope {
        case .all:
            break
        case .custom:
            if let s = customStart, let e = customEnd {
                let start = min(s, e)
                let end = max(s, e)
                resolvedRange = (start, end)
                pool = pool.filter { $0.timestamp >= start && $0.timestamp <= end }
            }
        case .intelligent:
            if let inferred = inferRange(from: question, now: now, calendar: calendar) {
                resolvedRange = inferred
                pool = pool.filter { $0.timestamp >= inferred.0 && $0.timestamp <= inferred.1 }
            }
            let keywords = extractTerms(from: question)
            if !keywords.isEmpty {
                let scored = pool.map { entry -> (CapsuleEntry, Int) in
                    let hay = [
                        entry.content,
                        entry.songInfo ?? "",
                        entry.mood ?? "",
                        entry.tags.joined(separator: " "),
                        entry.comments.map(\.text).joined(separator: " "),
                    ].joined(separator: " ").lowercased()
                    let score = keywords.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
                    return (entry, score)
                }
                let matched = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
                if !matched.isEmpty {
                    pool = matched
                }
            }
            pool = Array(pool.prefix(30))
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var buffer = ""
        var count = 0
        for entry in pool {
            var lines = ["[\(df.string(from: entry.timestamp))]"]
            if let mood = entry.mood { lines.append("心情/Mood: \(mood)") }
            if let song = entry.songInfo { lines.append("音乐/Song: \(song)") }
            if !entry.tags.isEmpty { lines.append("标签/Tags: \(entry.tags.joined(separator: ", "))") }
            if !entry.content.isEmpty { lines.append(entry.content) }
            if !entry.comments.isEmpty {
                let refs = entry.comments.map { "回看(\(df.string(from: $0.timestamp))): \($0.text)" }
                lines.append(contentsOf: refs)
            }
            let block = lines.joined(separator: "\n")
            let sep = buffer.isEmpty ? "" : "\n\n---\n\n"
            if buffer.count + sep.count + block.count > maxCharacters {
                let remaining = maxCharacters - buffer.count - sep.count
                if remaining > 40 {
                    buffer += sep + String(block.prefix(remaining))
                    count += 1
                }
                break
            }
            buffer += sep + block
            count += 1
        }

        return AiDisclosurePreview(
            providerName: providerName,
            recordCount: count,
            characterCount: buffer.count,
            includedFields: ["date", "content", "songInfo", "mood", "tags", "comments"],
            mediaBytesIncluded: false,
            previewText: buffer,
            dateStart: resolvedRange?.0,
            dateEnd: resolvedRange?.1
        )
    }

    public func executeRequest(
        settings: AiSettings,
        prompt: String,
        disclosure: AiDisclosurePreview,
        type: AiEntryType,
        questionTitle: String
    ) async throws -> AiEntry {
        let answer = try await sendRawCompletion(settings: settings, prompt: prompt)
        let entry = AiEntry(
            question: questionTitle,
            answer: answer,
            type: type,
            timestamp: Date(),
            contextStart: disclosure.dateStart,
            contextEnd: disclosure.dateEnd,
            comments: []
        )
        _ = try await repository.upsertAiEntry(entry)
        return entry
    }

    public func testConnection(settings: AiSettings) async throws -> String {
        try await sendRawCompletion(settings: settings, prompt: "Reply briefly with: OK (Pickup iOS connection verified).")
    }

    public func sendRawCompletion(settings: AiSettings, prompt: String) async throws -> String {
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw AiHubError.missingApiKey
        }
        let endpointStr = settings.provider == .custom ? settings.customEndpointURL : settings.provider.defaultEndpointURL
        guard let url = URL(string: endpointStr.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw AiHubError.invalidEndpointURL
        }

        var req = URLRequest(url: url, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let modelName = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "model": modelName.isEmpty ? settings.provider.defaultModel : modelName,
            "messages": [
                ["role": "system", "content": "You are Pickup's warm, insightful personal memory companion. Answer clearly and thoughtfully based strictly on the provided journal excerpts."],
                ["role": "user", "content": prompt],
            ],
            "temperature": 0.6,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errBody = String(data: data.prefix(240), encoding: .utf8) ?? ""
            throw AiHubError.httpFailure(http.statusCode, errBody)
        }

        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AiHubError.emptyResponse
        }
        let text = extractText(from: parsed).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AiHubError.emptyResponse
        }
        return text
    }

    private func extractText(from json: [String: Any]) -> String {
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return text
        }
        return ""
    }

    private static func inferRange(from question: String, now: Date, calendar: Calendar) -> (Date, Date)? {
        let year = calendar.component(.year, from: now)
        let lower = question.lowercased()
        if question.contains("去年") || lower.contains("last year") {
            let y = year - 1
            if let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)),
               let end = calendar.date(from: DateComponents(year: y, month: 12, day: 31, hour: 23, minute: 59, second: 59)) {
                return (start, end)
            }
        }
        if question.contains("今年") || lower.contains("this year") {
            if let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
               let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59)) {
                return (start, end)
            }
        }
        if let regex = try? NSRegularExpression(pattern: "(19|20)\\d{2}"),
           let match = regex.firstMatch(in: question, range: NSRange(question.startIndex..., in: question)),
           let range = Range(match.range, in: question),
           let y = Int(question[range]),
           let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)),
           let end = calendar.date(from: DateComponents(year: y, month: 12, day: 31, hour: 23, minute: 59, second: 59)) {
            return (start, end)
        }
        return nil
    }

    private static func extractTerms(from question: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，。！？；：、.!?;:"))
        let stopwords: Set<String> = ["什么", "怎么", "发生", "哪些", "最近", "please", "what", "when", "which", "about"]
        return question.lowercased()
            .components(separatedBy: separators)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }
}
