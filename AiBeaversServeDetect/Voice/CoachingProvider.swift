import Foundation

// Turns (player context, fault verdict) into one short spoken coaching line.
// Returns nil when no line is available within budget — the caller speaks a canned fallback.
protocol CoachingProvider {
    func coachingLine(for context: CoachContext, fault: Bool) async -> String?
}

// Calls Google Gemini Flash. Empty key, error, timeout, or an over-long reply all return
// nil so the caller falls back to the fixed line.
struct GeminiCoachingProvider: CoachingProvider {
    private let model = "gemini-2.5-flash-lite"
    private let timeoutSeconds = 1.2
    private let maxWords = 12   // hard guard above the 10-word target

    func coachingLine(for context: CoachContext, fault: Bool) async -> String? {
        guard !Secrets.geminiAPIKey.isEmpty else { return nil }
        do {
            return try await withTimeout(timeoutSeconds) {
                try await self.request(context: context, fault: fault)
            }
        } catch {
            print("CoachingProvider: gemini unavailable (\(error.localizedDescription)) — using canned line")
            return nil
        }
    }

    private func request(context: CoachContext, fault: Bool) async throws -> String? {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Secrets.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "system_instruction": ["parts": [["text": CoachingPrompt.master]]],
            "contents": [["role": "user", "parts": [["text": CoachingPrompt.userMessage(context, fault: fault)]]]],
            "generationConfig": [
                "temperature": 0.8,
                "maxOutputTokens": 32,
                "thinkingConfig": ["thinkingBudget": 0],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("CoachingProvider: gemini HTTP \(status), \(data.count) bytes")
        guard status == 200 else { return nil }
        return Self.firstShortSentence(from: data, maxWords: maxWords)
    }

    // Pulls candidates[0].content.parts[].text, keeps the first sentence, returns nil if empty or too long.
    static func firstShortSentence(from data: Data, maxWords: Int) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            return nil
        }

        let text = parts.compactMap { $0["text"] as? String }.joined()
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let terminators = CharacterSet(charactersIn: ".!?")
        let firstSentence: String
        if let idx = cleaned.unicodeScalars.firstIndex(where: { terminators.contains($0) }) {
            firstSentence = String(String.UnicodeScalarView(cleaned.unicodeScalars[...idx]))
        } else {
            firstSentence = cleaned
        }

        let line = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = line.split(separator: " ").count
        guard wordCount <= maxWords else {
            print("CoachingProvider: reply too long (\(wordCount) words) — using canned line")
            return nil
        }
        return line
    }
}

// Offline double: returns a fixed line (or nil) without any network. Swap point for other providers.
struct MockCoachingProvider: CoachingProvider {
    let line: String?
    func coachingLine(for context: CoachContext, fault: Bool) async -> String? { line }
}

// Runs `operation`, throwing TimeoutError if it does not finish within `seconds`.
private func withTimeout<T>(_ seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: Error {}
