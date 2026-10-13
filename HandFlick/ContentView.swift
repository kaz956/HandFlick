import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        Group {
            switch appModel.phase {
            case .setup: SetupView(model: appModel)
            case .instructions: InstructionView(model: appModel)
            case .running: ExperimentView(model: appModel)
            case .blockBreak, .conditionBreak: BreakView(model: appModel)
            case .questionnaire: QuestionnaireView(model: appModel)
            case .finalPreference: FinalPreferenceView(model: appModel)
            case .completed: CompletionView(model: appModel)
            }
        }
        .frame(minWidth: 760, minHeight: 620)
        .task { await appModel.prepare() }
        .onChange(of: appModel.phase) { _, phase in
            guard phase == .instructions, appModel.experiment.currentMethod == .handFlick, appModel.immersiveSpaceState == .closed else { return }
            appModel.immersiveSpaceState = .inTransition
            Task {
                switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                case .opened: break
                case .userCancelled: appModel.immersiveSpaceState = .closed; appModel.handTracker.statusMessage = "Immersive space opening was cancelled."
                case .error: appModel.immersiveSpaceState = .closed; appModel.handTracker.statusMessage = "Unable to open immersive space for Hand Tracking."
                @unknown default: appModel.immersiveSpaceState = .closed; appModel.handTracker.statusMessage = "Unknown immersive-space error."
                }
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView().environment(AppModel())
}
