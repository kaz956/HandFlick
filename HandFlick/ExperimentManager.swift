import Foundation
import Observation
import simd

@MainActor @Observable
final class ExperimentManager {
    var participantID = "P001"; var sessionID = "S01"; var config = ExperimentConfig()
    var conditionOrder: [InputMethod] = InputMethod.allCases
    var phraseSetByCondition: [String: String] = [:]
    var phrases: [Phrase] = []; var currentConditionIndex = 0; var currentTrialIndex = 0
    var enteredText = ""; var currentTrial: Phrase?; var isPractice = false
    var isUppercase = false
    var trialPresentedAt: Date?; var firstInputAt: Date?; var lastInputAt: Date?; var backspaceTimestamps: [Date] = []
    var questionnaires = QuestionnaireResponse(); var preference: InputMethod = .handFlick; var preferenceComment = ""
    private var logger: ExperimentLogger?; private var selectedPhrases: [InputMethod: [Phrase]] = [:]

    var currentMethod: InputMethod { conditionOrder[min(currentConditionIndex, conditionOrder.count - 1)] }
    var currentBlock: Int { currentTrialIndex / max(1, config.phrasesPerBlock) + 1 }
    var phraseInBlock: Int { currentTrialIndex % max(1, config.phrasesPerBlock) + 1 }
    var totalTrialsPerCondition: Int { config.numberOfBlocks * config.phrasesPerBlock }
    var currentPhraseSet: String { phraseSetByCondition[currentMethod.rawValue] ?? "A" }

    func loadPhrasesIfNeeded() async {
        guard phrases.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "Phrases", withExtension: "json"),
              let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Phrase].self, from: data) else { return }
        phrases = decoded
    }
    func applyCounterbalance() {
        let n = Int(participantID.filter(\.isNumber)) ?? 0
        let orders: [[InputMethod]] = [[.handFlick,.defaultDirect,.defaultGazePinch],[.handFlick,.defaultGazePinch,.defaultDirect],[.defaultDirect,.handFlick,.defaultGazePinch],[.defaultDirect,.defaultGazePinch,.handFlick],[.defaultGazePinch,.handFlick,.defaultDirect],[.defaultGazePinch,.defaultDirect,.handFlick]]
        conditionOrder = orders[n % orders.count]
        let sets = ["A", "B", "C"]
        phraseSetByCondition = Dictionary(uniqueKeysWithValues: InputMethod.allCases.enumerated().map { ($0.element.rawValue, sets[($0.offset + n) % sets.count]) })
    }
    func start(practice: Bool) async throws {
        guard !participantID.isEmpty, !sessionID.isEmpty else { throw ExperimentError.missingIdentity }
        guard !phrases.isEmpty else { throw ExperimentError.phrasesUnavailable }
        isPractice = practice; currentConditionIndex = 0; currentTrialIndex = 0; selectedPhrases.removeAll()
        for method in InputMethod.allCases {
            let set = phraseSetByCondition[method.rawValue] ?? "A"
            let pool = phrases.filter { $0.setID == set }
            guard !pool.isEmpty else { throw ExperimentError.phrasesUnavailable }
            // Cycles only if the supplied dataset has fewer items than the configured trial count.
            selectedPhrases[method] = (0..<totalTrialsPerCondition).map { pool[$0 % pool.count] }
        }
        logger = try ExperimentLogger(participantID: participantID, sessionID: sessionID)
        try logger?.writeConfiguration(config, order: conditionOrder, phraseSets: phraseSetByCondition, practice: practice)
    }
    func beginCurrentCondition() { presentTrial() }
    func presentTrial() {
        enteredText = ""; isUppercase = false; firstInputAt = nil; lastInputAt = nil; backspaceTimestamps = []; trialPresentedAt = Date()
        currentTrial = selectedPhrases[currentMethod]?[currentTrialIndex]
        log(type: .phrasePresented, before: "", after: "")
    }
    func acceptTextChange(_ newText: String) {
        let old = enteredText; guard newText != old else { return }
        let event = TextChange.classify(before: old, after: newText)
        enteredText = newText; let now = Date(); if firstInputAt == nil { firstInputAt = now; log(type: .trialFirstInput, before: old, after: newText, timestamp: now) }; lastInputAt = now
        if event.type == .backspace { backspaceTimestamps.append(now) }
        log(type: event.type, before: old, after: newText, inserted: event.inserted, deleted: event.deleted, timestamp: now)
    }
    func acceptHandFlick(_ primitive: HandFlickPrimitive, metadata: HandFlickMetadata) {
        guard let output = config.layout.output(for: primitive) else { return }
        if output == EnglishHandFlickLayout.caseToggleOutput {
            isUppercase.toggle()
            log(type: .caseToggle, before: enteredText, after: enteredText)
            logger?.logHandFlick(metadata, primitive: primitive, output: isUppercase ? "uppercase" : "lowercase", context: context())
            return
        }
        let inserted = isUppercase ? output.uppercased() : output
        let next = inserted == "\u{8}" ? String(enteredText.dropLast()) : enteredText + inserted
        acceptTextChange(next)
        logger?.logHandFlick(metadata, primitive: primitive, output: inserted, context: context())
    }
    func finishTrial() async -> AppModel.Phase {
        let done = Date(); log(type: .done, before: enteredText, after: enteredText, timestamp: done)
        logger?.logTrial(TrialRecord(context: context(), target: currentTrial?.text ?? "", transcribed: enteredText, presented: trialPresentedAt, firstInput: firstInputAt, lastInput: lastInputAt, done: done, backspaces: backspaceTimestamps))
        logger?.flush()
        currentTrialIndex += 1
        if currentTrialIndex < totalTrialsPerCondition {
            if config.breakAfterEachBlock && currentTrialIndex % config.phrasesPerBlock == 0 { return .blockBreak }
            presentTrial(); return .running
        }
        logger?.flush()
        return .questionnaire
    }
    func advanceAfterBreak() { presentTrial() }
    func saveQuestionnaireAndAdvance() async -> AppModel.Phase {
        logger?.logQuestionnaire(questionnaires, method: currentMethod, practice: isPractice); logger?.flush()
        questionnaires = QuestionnaireResponse(); currentConditionIndex += 1; currentTrialIndex = 0
        if currentConditionIndex >= conditionOrder.count { return .finalPreference }
        return config.breakAfterEachCondition ? .conditionBreak : .instructions
    }
    func saveFinalPreference() async { logger?.logPreference(preference, comment: preferenceComment); logger?.flush() }
    func logTrackingTransition(available: Bool) { log(type: available ? .trackingRecovered : .trackingLost, before: enteredText, after: enteredText) }
    func logHandSample(_ sample: HandJointSample, localPosition: SIMD3<Float>?) { logger?.logHandSample(sample, context: context(), localPosition: localPosition) }
    private func context() -> LogContext { .init(participant: participantID, session: sessionID, method: currentMethod, order: currentConditionIndex, phraseSet: currentPhraseSet, block: currentBlock, trial: currentTrialIndex + 1, phraseID: currentTrial?.id ?? "", practice: isPractice) }
    private func log(type: InputEventType, before: String, after: String, inserted: String = "", deleted: String = "", timestamp: Date = Date()) { logger?.logEvent(.init(context: context(), timestamp: timestamp, type: type, before: before, after: after, inserted: inserted, deleted: deleted, firstInput: firstInputAt)) }
}
enum ExperimentError: LocalizedError { case missingIdentity, phrasesUnavailable
    var errorDescription: String? { switch self { case .missingIdentity: "Participant ID and Session ID are required."; case .phrasesUnavailable: "Phrases.json could not be loaded. Confirm it is included in the app target." } }
}
enum InputEventType: String, Codable { case phrasePresented = "phrase_presented", trialFirstInput = "trial_first_input", characterInput = "character_input", space, backspace, caseToggle = "case_toggle", textReplacement = "text_replacement", done, trackingLost = "tracking_lost", trackingRecovered = "tracking_recovered" }
struct TextChange { let type: InputEventType; let inserted: String; let deleted: String
    static func classify(before: String, after: String) -> TextChange {
        if after == before + " " { return .init(type: .space, inserted: " ", deleted: "") }
        if after.count == before.count + 1, after.hasPrefix(before) { return .init(type: .characterInput, inserted: String(after.suffix(1)), deleted: "") }
        if before.count == after.count + 1, before.hasPrefix(after) { return .init(type: .backspace, inserted: "", deleted: String(before.suffix(1))) }
        return .init(type: .textReplacement, inserted: "", deleted: "")
    }
}
