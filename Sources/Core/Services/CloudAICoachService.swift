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

    // Structured outputs stay on curated content until we design their
    // server-side prompts — the free-form surfaces are live AI already.
    func weeklyReport(relationship: Relationship, events: [RelationshipEvent]) async throws -> [AIInsight] {
        try await fallback.weeklyReport(relationship: relationship, events: events)
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
