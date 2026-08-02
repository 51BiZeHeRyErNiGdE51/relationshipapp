import FirebaseFunctions
import Foundation

// MARK: - Cloud AI Coach (DeepSeek via Cloud Functions)
//
// The DeepSeek API key never ships in the app — it lives in a Cloud Functions
// secret (`DEEPSEEK_API_KEY`) and the `askCoach` callable builds the couple's
// context (rated question answers, alignment, moods) server-side from
// Firestore. If the function isn't deployed yet or errors, we degrade to the
// demo coach so the UI never breaks.

struct CloudAICoachService: AICoachService {
    private let fallback = DemoAICoachService()

    func chat(message: String, relationship: Relationship) async throws -> String {
        do {
            return try await ask(mode: "chat", message: message, relationship: relationship)
        } catch {
            return try await fallback.chat(message: message, relationship: relationship)
        }
    }

    func dateIdeas(relationship: Relationship) async throws -> [String] {
        do {
            let reply = try await ask(mode: "dateIdeas",
                                      message: "Suggest date ideas for us.",
                                      relationship: relationship)
            let ideas = reply
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !ideas.isEmpty else { throw LovioError.notSignedIn }
            return ideas
        } catch {
            return try await fallback.dateIdeas(relationship: relationship)
        }
    }

    /// Live DeepSeek report over the couple's real Firestore context.
    /// Server replies 3 lines of "Title | body"; falls back to the local
    /// stats-based report if the function is unreachable.
    func weeklyReport(relationship: Relationship, events: [RelationshipEvent]) async throws -> [AIInsight] {
        do {
            let reply = try await ask(mode: "weeklyReport",
                                      message: "Write our weekly relationship report.",
                                      relationship: relationship)
            let symbols = ["waveform.path.ecg", "heart.text.square", "sparkles"]
            let insights = reply
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.contains("|") }
                .prefix(3)
                .enumerated()
                .map { index, line -> AIInsight in
                    let parts = line.split(separator: "|", maxSplits: 1).map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    return AIInsight(title: parts.first ?? "This week",
                                     body: parts.count > 1 ? parts[1] : line,
                                     symbol: symbols[index % symbols.count])
                }
            guard !insights.isEmpty else { throw LovioError.notSignedIn }
            return Array(insights)
        } catch {
            return try await fallback.weeklyReport(relationship: relationship, events: events)
        }
    }

    func conversationStarters(relationship: Relationship) async throws -> [String] {
        try await fallback.conversationStarters(relationship: relationship)
    }

    // MARK: Callable plumbing

    private func ask(mode: String, message: String, relationship: Relationship) async throws -> String {
        let result = try await Functions.functions()
            .httpsCallable("askCoach")
            .call(["mode": mode,
                   "message": message,
                   "relationshipID": relationship.id])
        guard let data = result.data as? [String: Any],
              let reply = data["reply"] as? String, !reply.isEmpty else {
            throw LovioError.notSignedIn
        }
        return reply
    }
}
