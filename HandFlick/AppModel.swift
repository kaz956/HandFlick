import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case setup, instructions, running, blockBreak, conditionBreak, questionnaire, finalPreference, completed }
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState { case closed, inTransition, open }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    var experiment = ExperimentManager()
    /// Shared with ImmersiveView. ARKit hand tracking is started only after the immersive space opens.
    var handTracker = HandTrackingManager()
    var phase: Phase = .setup
    var setupError: String?
    var debugMessage = ""

    func prepare() async { await experiment.loadPhrasesIfNeeded() }
    func start(practice: Bool) async {
        do { try await experiment.start(practice: practice); phase = .instructions }
        catch { setupError = error.localizedDescription }
    }
    func beginCondition() { experiment.beginCurrentCondition(); phase = .running }
    func finishTrial() async { phase = await experiment.finishTrial() }
    func continueAfterBreak() {
        if phase == .conditionBreak { phase = .instructions }
        else { experiment.advanceAfterBreak(); phase = .running }
    }
    func submitQuestionnaire() async { phase = await experiment.saveQuestionnaireAndAdvance() }
    func submitPreference() async { await experiment.saveFinalPreference(); phase = .completed }
}
