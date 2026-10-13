import SwiftUI

struct SetupView: View {
    @Bindable var model: AppModel
    var body: some View { Form {
        Section("Experimenter Setup") { TextField("Participant ID", text: $model.experiment.participantID); TextField("Session ID", text: $model.experiment.sessionID); Button("Apply counterbalance") { model.experiment.applyCounterbalance() }; Text("Order: \(model.experiment.conditionOrder.map(\.title).joined(separator: " → "))").font(.caption) }
        Section("Phrase sets") { ForEach(InputMethod.allCases) { method in Picker(method.title, selection: Binding(get: { model.experiment.phraseSetByCondition[method.rawValue] ?? "A" }, set: { model.experiment.phraseSetByCondition[method.rawValue] = $0 })) { Text("A").tag("A"); Text("B").tag("B"); Text("C").tag("C") } } }
        Section("Structure") { Stepper("Blocks: \(model.experiment.config.numberOfBlocks)", value: $model.experiment.config.numberOfBlocks, in: 1...10); Stepper("Phrases per block: \(model.experiment.config.phrasesPerBlock)", value: $model.experiment.config.phrasesPerBlock, in: 1...24); Toggle("Debug mode", isOn: $model.experiment.config.enableDebugView) }
        if let error = model.setupError { Text(error).foregroundStyle(.red) }
        HStack { Button("Start Practice") { Task { await model.start(practice: true) } }; Button("Start Main Experiment") { Task { await model.start(practice: false) } }.buttonStyle(.borderedProminent) }
    }.padding().onAppear { if model.experiment.phraseSetByCondition.isEmpty { model.experiment.applyCounterbalance() } } }
}
struct InstructionView: View { let model: AppModel
    var body: some View { VStack(spacing: 28) { Text(model.experiment.currentMethod.title).font(.largeTitle); Text(model.experiment.currentMethod.instruction).multilineTextAlignment(.center).font(.title3); Text("Please enter the presented phrase as quickly and accurately as possible. If you notice an error, correct it as you normally would.").multilineTextAlignment(.center); Button("Begin") { model.beginCondition() }.buttonStyle(.borderedProminent).controlSize(.large) }.padding(80) }
}
struct ExperimentView: View {
    @Bindable var model: AppModel
    @FocusState private var systemFieldFocused: Bool
    private var handTracker: HandTrackingManager { model.handTracker }
    var body: some View { VStack(alignment: .leading, spacing: 24) {
        Text("TARGET").font(.headline); Text(model.experiment.currentTrial?.text ?? "").font(.system(size: 32, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
        Text("ENTERED").font(.headline)
        if model.experiment.currentMethod == .handFlick { Text(model.experiment.enteredText + "_").font(.system(size: 32)).frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel("Entered text") }
        else { TextField("Enter phrase", text: Binding(get: { model.experiment.enteredText }, set: { model.experiment.acceptTextChange($0) }), axis: .vertical).focused($systemFieldFocused).font(.system(size: 32)).textInputAutocapitalization(.never).autocorrectionDisabled(true).keyboardType(.asciiCapable).frame(maxWidth: .infinity, alignment: .leading) }
        Text("\(model.experiment.currentMethod.title)\nBlock \(model.experiment.currentBlock) / \(model.experiment.config.numberOfBlocks)    Phrase \(model.experiment.phraseInBlock) / \(model.experiment.config.phrasesPerBlock)").foregroundStyle(.secondary)
        HStack { Spacer(); Button("Done") { Task { await model.finishTrial() } }.buttonStyle(.borderedProminent).controlSize(.large) }
        if model.experiment.config.enableDebugView { DebugView(tracker: handTracker) }
    }.padding(64).task(id: model.experiment.currentMethod) {
        guard model.experiment.currentMethod == .handFlick else { systemFieldFocused = true; return }
        handTracker.onPrimitive = { primitive, metadata in model.experiment.acceptHandFlick(primitive, metadata: metadata) }; handTracker.onTrackingChanged = { model.experiment.logTrackingTransition(available: $0) }; handTracker.onSample = { sample, local in model.experiment.logHandSample(sample, localPosition: local) }
    } }
}
struct DebugView: View { let tracker: HandTrackingManager
    var body: some View { VStack(alignment: .leading) { Divider(); Text("DEBUG").font(.headline); Text("Left Hand Tracking: \(tracker.leftAvailable ? "OK" : "Unavailable")\nRight Hand Tracking: \(tracker.rightAvailable ? "OK" : "Unavailable")\nStatus: \(tracker.statusMessage)\nCurrent Region: \(tracker.currentRegion?.id ?? "—")\nContact Distance: \(tracker.contactDistance, format: .number.precision(.fractionLength(3)))\nCurrent Action: \(tracker.currentAction?.rawValue ?? "—")\nState: \(tracker.state.rawValue)").font(.caption.monospaced()) } }
}
struct BreakView: View { let model: AppModel
    var body: some View { VStack(spacing: 24) { Text(model.phase == .blockBreak ? "Block \(model.experiment.currentBlock - 1) completed." : "\(model.experiment.currentMethod.title) condition completed.").font(.largeTitle); Text(model.phase == .blockBreak ? "Please take a short break." : "Please remove the headset or rest if needed."); Button("Continue") { model.continueAfterBreak() }.buttonStyle(.borderedProminent) }.padding(80) }
}
struct QuestionnaireView: View { @Bindable var model: AppModel
    private func slider(_ title: String, _ value: Binding<Double>) -> some View { VStack(alignment: .leading) { Text("\(title): \(Int(value.wrappedValue))"); Slider(value: value, in: 0...100, step: 1) } }
    private func likert(_ title: String, _ value: Binding<Int>) -> some View { Picker(title, selection: value) { ForEach(1...7, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented) }
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 16) { Text("Questionnaire — \(model.experiment.currentMethod.title)").font(.title); Group { slider("Mental Demand", $model.experiment.questionnaires.mental); slider("Physical Demand", $model.experiment.questionnaires.physical); slider("Temporal Demand", $model.experiment.questionnaires.temporal); slider("Performance", $model.experiment.questionnaires.performance); slider("Effort", $model.experiment.questionnaires.effort); slider("Frustration", $model.experiment.questionnaires.frustration) }; Text("1 = Strongly disagree     7 = Strongly agree").font(.caption); Group { likert("Comfort", $model.experiment.questionnaires.comfort); likert("Hand Fatigue", $model.experiment.questionnaires.handFatigue); likert("Arm Fatigue", $model.experiment.questionnaires.armFatigue); likert("Input Confidence", $model.experiment.questionnaires.confidence); likert("Learnability", $model.experiment.questionnaires.learnability); likert("Overall Satisfaction", $model.experiment.questionnaires.satisfaction) }; Button("Save and continue") { Task { await model.submitQuestionnaire() } }.buttonStyle(.borderedProminent) }.padding(48) } }
}
struct FinalPreferenceView: View { @Bindable var model: AppModel
    var body: some View { VStack(alignment: .leading, spacing: 24) { Text("Which input method would you prefer to use for text entry on Vision Pro?").font(.title2); Picker("Preference", selection: $model.experiment.preference) { ForEach(InputMethod.allCases) { Text($0.title).tag($0) } }; TextField("Optional comment", text: $model.experiment.preferenceComment, axis: .vertical); Button("Finish experiment") { Task { await model.submitPreference() } }.buttonStyle(.borderedProminent) }.padding(64) }
}
struct CompletionView: View { let model: AppModel
    var body: some View { VStack(spacing: 20) { Text("Experiment completed.").font(.largeTitle); Text("Participant: \(model.experiment.participantID)\nSession: \(model.experiment.sessionID)\n\nData saved successfully in the app Documents/HandFlickData folder.").multilineTextAlignment(.center) }.padding(80) }
}
