import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import FirebaseAnalytics
import FirebaseRemoteConfig
import FirebaseStorage
import GoogleSignIn
import UIKit

// MARK: - Firestore schema (platform-independent)
//
//   users/{userID}                          → UserProfile
//   invites/{CODE}                          → { relationshipID }
//   relationships/{relID}                   → Relationship
//   relationships/{relID}/journal/{id}      → JournalEntry
//   relationships/{relID}/moods/{id}        → MoodEntry
//   relationships/{relID}/dates/{id}        → SpecialDate
//   relationships/{relID}/bucket/{id}       → BucketListItem
//   relationships/{relID}/milestones/{id}   → Milestone
//   relationships/{relID}/notes/{id}        → SharedNote
//   relationships/{relID}/events/{id}       → RelationshipEvent   (relationship graph)
//   relationships/{relID}/answers/{qID_uID} → QuestionAnswer
//   relationships/{relID}/premium/state     → PremiumEntitlement  (synced by purchaser/webhook)
//
// All IDs are opaque strings. Android clients read/write the same documents.

enum FirebaseBootstrap {
    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    /// Returns true when a GoogleService-Info.plist is bundled and Firebase started.
    @discardableResult
    static func configureIfPossible() -> Bool {
        guard FirebaseApp.app() == nil else { return true }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return false
        }
        FirebaseApp.configure()
        return true
    }
}

// MARK: - Auth

final class FirebaseAuthService: NSObject, AuthService, @unchecked Sendable {
    private var currentNonce: String?
    private var appleContinuation: CheckedContinuation<AuthenticatedUser, Error>?

    func currentUser() async -> AuthenticatedUser? {
        guard let user = Auth.auth().currentUser else { return nil }
        // Empty (NOT "You") when unnamed — Home shows the name-capture card.
        return AuthenticatedUser(id: user.uid,
                                 displayName: user.displayName ?? "",
                                 email: user.email)
    }

    func signIn(with provider: AuthProviderKind) async throws -> AuthenticatedUser {
        switch provider {
        case .anonymous: try await signInAnonymously()
        case .apple: try await signInWithApple()
        case .google: try await signInWithGoogle()
        case .demo: throw LovioError.notSignedIn
        }
    }

    private func signInAnonymously() async throws -> AuthenticatedUser {
        let result = try await Auth.auth().signInAnonymously()
        return AuthenticatedUser(id: result.user.uid, displayName: "", email: nil)
    }

    func signOut() async throws {
        try Auth.auth().signOut()
    }

    func deleteAccount() async throws {
        try await Auth.auth().currentUser?.delete()
    }

    // MARK: Sign in with Apple (nonce-hardened)

    @MainActor
    private func signInWithApple() async throws -> AuthenticatedUser {
        let nonce = Self.randomNonce()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.appleContinuation = continuation
            controller.performRequests()
        }
    }

    // MARK: Google Sign-In

    @MainActor
    private func signInWithGoogle() async throws -> AuthenticatedUser {
        guard let clientID = FirebaseApp.app()?.options.clientID else { throw LovioError.notSignedIn }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else { throw LovioError.notSignedIn }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        guard let idToken = result.user.idToken?.tokenString else { throw LovioError.notSignedIn }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                       accessToken: result.user.accessToken.tokenString)
        let authResult = try await Auth.auth().signIn(with: credential)
        return AuthenticatedUser(id: authResult.user.uid,
                                 displayName: authResult.user.displayName ?? "",
                                 email: authResult.user.email)
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFabcdef-._")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension FirebaseAuthService: ASAuthorizationControllerDelegate,
                                ASAuthorizationControllerPresentationContextProviding {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            appleContinuation?.resume(throwing: LovioError.notSignedIn)
            appleContinuation = nil
            return
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: token, rawNonce: nonce, fullName: credential.fullName)

        Task {
            do {
                let result = try await Auth.auth().signIn(with: firebaseCredential)
                let name = credential.fullName.flatMap {
                    PersonNameComponentsFormatter().string(from: $0)
                }
                if let name, !name.isEmpty, result.user.displayName == nil {
                    let change = result.user.createProfileChangeRequest()
                    change.displayName = name
                    try? await change.commitChanges()
                }
                self.appleContinuation?.resume(returning: AuthenticatedUser(
                    id: result.user.uid,
                    displayName: result.user.displayName ?? name ?? "",
                    email: result.user.email))
            } catch {
                self.appleContinuation?.resume(throwing: error)
            }
            self.appleContinuation = nil
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        appleContinuation?.resume(throwing: error)
        appleContinuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

// MARK: - Relationship

struct FirestoreRelationshipService: RelationshipService {
    private var db: Firestore { Firestore.firestore() }

    func currentRelationship(for user: UserID) async throws -> Relationship? {
        // Single-field query (no composite index needed); status filtered locally.
        // An ACTIVE (paired) relationship always beats a pending solo one —
        // this is also how the creator's device discovers the partner joined.
        let snapshot = try await db.collection("relationships")
            .whereField("memberIDs", arrayContains: user)
            .getDocuments()
        var candidates: [Relationship] = snapshot.documents.compactMap {
            try? $0.data(as: Relationship.self)
        }
        candidates = candidates.filter { rel in
            rel.status == .active || rel.status == .pendingPartner
        }
        candidates.sort { $0.createdAt > $1.createdAt }
        let active = candidates.first { rel in rel.status == .active }
        return active ?? candidates.first
    }

    func createRelationship(creator: UserID, anniversary: Date?) async throws -> Relationship {
        let relationship = Relationship(memberIDs: [creator], createdBy: creator,
                                        anniversary: anniversary)
        try db.collection("relationships").document(relationship.id)
            .setData(from: relationship)
        if let code = relationship.inviteCode?.value {
            try await db.collection("invites").document(code)
                .setData(["relationshipID": relationship.id])
        }
        return relationship
    }

    func joinRelationship(code: String, joiner: UserID) async throws -> Relationship {
        let normalized = code.replacingOccurrences(of: "-", with: "").uppercased()
        let invite = try await db.collection("invites").document(normalized).getDocument()
        guard let relID = invite.data()?["relationshipID"] as? String else {
            throw LovioError.invalidInviteCode
        }
        let ref = db.collection("relationships").document(relID)
        var relationship = try await ref.getDocument(as: Relationship.self)
        // Stale codes must never resurrect an ended (or already full)
        // relationship — that silently puts the couple in different spaces.
        guard relationship.status == .pendingPartner else {
            throw LovioError.invalidInviteCode
        }
        // Entering your OWN code must never "activate" a solo relationship.
        guard !relationship.memberIDs.contains(joiner) else {
            throw LovioError.cantPairWithSelf
        }
        guard relationship.memberIDs.count < 2 else {
            throw LovioError.relationshipFull
        }
        relationship.memberIDs.append(joiner)
        relationship.status = .active
        try ref.setData(from: relationship)
        return relationship
    }

    func endRelationship(_ id: RelationshipID, endedBy: UserID) async throws {
        // Kill the invite code first so stale codes can't be redeemed later.
        if let rel = try? await db.collection("relationships").document(id)
            .getDocument(as: Relationship.self),
           let code = rel.inviteCode?.value {
            try? await db.collection("invites").document(code).delete()
        }
        try await db.collection("relationships").document(id).updateData([
            "status": RelationshipStatus.ended.rawValue,
            "endedAt": Timestamp(date: .now),
        ])
    }

    func updateAnniversary(_ id: RelationshipID, date: Date) async throws {
        try await db.collection("relationships").document(id)
            .updateData(["anniversary": Timestamp(date: date)])
    }

    func profile(for user: UserID) async throws -> UserProfile? {
        try? await db.collection("users").document(user).getDocument(as: UserProfile.self)
    }

    func updateProfile(_ profile: UserProfile) async throws {
        try db.collection("users").document(profile.id).setData(from: profile)
    }

    func record(event: RelationshipEvent, relationship: RelationshipID) async throws {
        try db.collection("relationships").document(relationship)
            .collection("events").document(event.id).setData(from: event)
    }

    func recentEvents(relationship: RelationshipID, limit: Int) async throws -> [RelationshipEvent] {
        let snapshot = try await db.collection("relationships").document(relationship)
            .collection("events")
            .order(by: "occurredAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: RelationshipEvent.self) }
    }

    func updateGamification(_ relationship: Relationship) async throws {
        try db.collection("relationships").document(relationship.id)
            .setData(from: relationship, merge: true)
    }

    // MARK: Shared widget content + image storage

    // One document PER AUTHOR (widgetContent/{userID}) — a shared doc meant
    // both partners overwrote each other's photo/note (last writer wins).
    func widgetContent(relationship: RelationshipID, author: UserID) async throws -> SharedWidgetContent? {
        let doc = try await db.collection("relationships").document(relationship)
            .collection("widgetContent").document(author).getDocument()
        return try? doc.data(as: SharedWidgetContent.self)
    }

    func saveWidgetContent(_ content: SharedWidgetContent, relationship: RelationshipID, author: UserID) async throws {
        try db.collection("relationships").document(relationship)
            .collection("widgetContent").document(author).setData(from: content, merge: true)
    }

    func uploadImage(_ jpeg: Data, relationship: RelationshipID, fileName: String) async throws -> String {
        let path = "relationships/\(relationship)/\(fileName)"
        let ref = Storage.storage().reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(jpeg, metadata: metadata)
        return path
    }

    func downloadImage(path: String) async throws -> Data {
        try await Storage.storage().reference(withPath: path)
            .data(maxSize: 8 * 1024 * 1024)
    }
}

// MARK: - Questions

struct FirestoreQuestionService: QuestionService {
    private var db: Firestore { Firestore.firestore() }

    func todayState(relationship: RelationshipID, me: UserID) async throws -> DailyQuestionState {
        let question = QuestionBank.question(for: DayKey.today())
        let answers = try await fetchAnswers(question.id, relationship: relationship)
        return assemble(question, answers: answers, me: me)
    }

    func submitAnswer(_ text: String, rating: Int?, question: DailyQuestion,
                      relationship: RelationshipID, author: UserID) async throws -> DailyQuestionState {
        let answer = QuestionAnswer(id: "\(question.id)_\(author)",
                                    questionID: question.id, authorID: author, text: text,
                                    rating: rating, questionText: question.text)
        try db.collection("relationships").document(relationship)
            .collection("answers").document(answer.id).setData(from: answer)
        let answers = try await fetchAnswers(question.id, relationship: relationship)
        return assemble(question, answers: answers, me: author)
    }

    func history(relationship: RelationshipID, limit: Int) async throws -> [DailyQuestionState] {
        let snapshot = try await db.collection("relationships").document(relationship)
            .collection("answers")
            .order(by: "answeredAt", descending: true)
            .limit(to: limit * 2)
            .getDocuments()
        let answers = snapshot.documents.compactMap { try? $0.data(as: QuestionAnswer.self) }
        let grouped = Dictionary(grouping: answers, by: \.questionID)
        return grouped.compactMap { questionID, answers in
            guard answers.count == 2,
                  let dayKey = questionID.split(separator: "_").last.map(String.init) else { return nil }
            let question = QuestionBank.question(for: dayKey)
            return DailyQuestionState(question: question,
                                      myAnswer: answers.first,
                                      partnerHasAnswered: true,
                                      revealedAnswers: answers)
        }
        .sorted { ($0.revealedAnswers.first?.answeredAt ?? .distantPast) >
                  ($1.revealedAnswers.first?.answeredAt ?? .distantPast) }
    }

    private func fetchAnswers(_ questionID: String, relationship: RelationshipID) async throws -> [QuestionAnswer] {
        let snapshot = try await db.collection("relationships").document(relationship)
            .collection("answers")
            .whereField("questionID", isEqualTo: questionID)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: QuestionAnswer.self) }
    }

    private func assemble(_ q: DailyQuestion, answers: [QuestionAnswer], me: UserID) -> DailyQuestionState {
        let mine = answers.first { $0.authorID == me }
        let partners = answers.first { $0.authorID != me }
        return DailyQuestionState(question: q, myAnswer: mine,
                                  partnerHasAnswered: partners != nil,
                                  revealedAnswers: (mine != nil && partners != nil) ? answers : [])
    }
}

// MARK: - Journal / Mood / Planner (thin Codable CRUD over subcollections)

struct FirestoreJournalService: JournalService {
    private var db: Firestore { Firestore.firestore() }
    private func col(_ rel: RelationshipID) -> CollectionReference {
        db.collection("relationships").document(rel).collection("journal")
    }

    func entries(relationship: RelationshipID) async throws -> [JournalEntry] {
        try await col(relationship).order(by: "createdAt", descending: true).limit(to: 100)
            .getDocuments().documents.compactMap { try? $0.data(as: JournalEntry.self) }
    }
    func add(_ entry: JournalEntry, relationship: RelationshipID) async throws {
        try col(relationship).document(entry.id).setData(from: entry)
    }
    func react(entryID: String, relationship: RelationshipID, user: UserID, emoji: String) async throws {
        try await col(relationship).document(entryID).updateData(["reactions.\(user)": emoji])
    }
    func delete(entryID: String, relationship: RelationshipID) async throws {
        try await col(relationship).document(entryID).delete()
    }
}

struct FirestoreMoodService: MoodService {
    private var db: Firestore { Firestore.firestore() }
    private func col(_ rel: RelationshipID) -> CollectionReference {
        db.collection("relationships").document(rel).collection("moods")
    }

    func latestMoods(relationship: RelationshipID) async throws -> [UserID: MoodEntry] {
        let entries = try await history(relationship: relationship, days: 2)
        var latest: [UserID: MoodEntry] = [:]
        for entry in entries where latest[entry.authorID] == nil { latest[entry.authorID] = entry }
        return latest
    }
    func log(_ entry: MoodEntry, relationship: RelationshipID) async throws {
        try col(relationship).document(entry.id).setData(from: entry)
    }
    func history(relationship: RelationshipID, days: Int) async throws -> [MoodEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        return try await col(relationship)
            .whereField("loggedAt", isGreaterThan: Timestamp(date: cutoff))
            .order(by: "loggedAt", descending: true)
            .getDocuments().documents.compactMap { try? $0.data(as: MoodEntry.self) }
    }
}

struct FirestorePlannerService: PlannerService {
    private var db: Firestore { Firestore.firestore() }
    private func col(_ rel: RelationshipID, _ name: String) -> CollectionReference {
        db.collection("relationships").document(rel).collection(name)
    }

    func specialDates(relationship: RelationshipID) async throws -> [SpecialDate] {
        try await col(relationship, "dates").getDocuments().documents
            .compactMap { try? $0.data(as: SpecialDate.self) }
            .sorted { $0.daysUntil < $1.daysUntil }
    }
    func save(_ date: SpecialDate, relationship: RelationshipID) async throws {
        try col(relationship, "dates").document(date.id).setData(from: date)
    }
    func deleteDate(id: String, relationship: RelationshipID) async throws {
        try await col(relationship, "dates").document(id).delete()
    }
    func bucketList(relationship: RelationshipID) async throws -> [BucketListItem] {
        try await col(relationship, "bucket").getDocuments().documents
            .compactMap { try? $0.data(as: BucketListItem.self) }
    }
    func save(_ item: BucketListItem, relationship: RelationshipID) async throws {
        try col(relationship, "bucket").document(item.id).setData(from: item)
    }
    func milestones(relationship: RelationshipID) async throws -> [Milestone] {
        try await col(relationship, "milestones").getDocuments().documents
            .compactMap { try? $0.data(as: Milestone.self) }
            .sorted { $0.date < $1.date }
    }
    func save(_ milestone: Milestone, relationship: RelationshipID) async throws {
        try col(relationship, "milestones").document(milestone.id).setData(from: milestone)
    }
    func notes(relationship: RelationshipID) async throws -> [SharedNote] {
        try await col(relationship, "notes").getDocuments().documents
            .compactMap { try? $0.data(as: SharedNote.self) }
            .sorted { ($0.isPinned ? 0 : 1, $1.updatedAt) < ($1.isPinned ? 0 : 1, $0.updatedAt) }
    }
    func save(_ note: SharedNote, relationship: RelationshipID) async throws {
        try col(relationship, "notes").document(note.id).setData(from: note)
    }
    func deleteNote(id: String, relationship: RelationshipID) async throws {
        try await col(relationship, "notes").document(id).delete()
    }
}

// MARK: - GA4 sink

struct FirebaseAnalyticsClient: AnalyticsClient {
    func track(_ event: AnalyticsEvent) {
        FirebaseAnalytics.Analytics.logEvent(event.name, parameters: event.parameters)
    }
    func setUserProperty(_ value: String?, forName name: String) {
        FirebaseAnalytics.Analytics.setUserProperty(value, forName: name)
    }
}

// MARK: - Remote Config experiments

final class RemoteConfigExperiments: ExperimentsService, @unchecked Sendable {
    private let config = RemoteConfig.remoteConfig()

    init() {
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        config.configSettings = settings
        config.setDefaults([
            "paywall_headline": "control" as NSString,
            "onboarding_order": "control" as NSString,
            "daily_reminder_hour": "20" as NSString,
        ])
    }

    func variant(for experiment: String) -> String {
        config.configValue(forKey: experiment).stringValue
    }

    func refresh() async {
        _ = try? await config.fetchAndActivate()
    }
}
