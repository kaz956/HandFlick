import Foundation
import simd

struct LogContext { let participant: String; let session: String; let method: InputMethod; let order: Int; let phraseSet: String; let block: Int; let trial: Int; let phraseID: String; let practice: Bool }
struct EventRecord { let context: LogContext; let timestamp: Date; let type: InputEventType; let before: String; let after: String; let inserted: String; let deleted: String; let firstInput: Date? }
struct TrialRecord { let context: LogContext; let target: String; let transcribed: String; let presented: Date?; let firstInput: Date?; let lastInput: Date?; let done: Date; let backspaces: [Date] }
struct HandFlickMetadata { let contactStart: Date; let recognitionTime: Date; let contactDistance: Float; let maximumDisplacement: Float; let leftAvailable: Bool; let rightAvailable: Bool }
struct QuestionnaireResponse { var mental = 50.0; var physical = 50.0; var temporal = 50.0; var performance = 50.0; var effort = 50.0; var frustration = 50.0; var comfort = 4; var handFatigue = 4; var armFatigue = 4; var confidence = 4; var learnability = 4; var satisfaction = 4 }

/// Buffered, append-only CSV writer. All fields are RFC-4180 escaped and flushes occur at trial boundaries.
final class ExperimentLogger {
    let directory: URL; private let participantID: String; private let sessionID: String; private var buffers: [String: [String]] = [:]
    init(participantID: String, sessionID: String) throws {
        self.participantID = participantID; self.sessionID = sessionID
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safe = { (value: String) in value.replacingOccurrences(of: "/", with: "_") }
        let base = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = base.appendingPathComponent("HandFlickData", isDirectory: true).appendingPathComponent("\(safe(participantID))_\(safe(sessionID))_\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        create("trial_log.csv", header: "participant_id,session_id,condition,condition_order_index,phrase_set,block,trial,phrase_id,target_text,transcribed_text,trial_presented_timestamp,first_input_timestamp,last_input_timestamp,done_timestamp,input_duration_sec,total_trial_duration_sec,total_input_events,character_insertions,backspace_count,space_count,is_practice")
        create("event_log.csv", header: "participant_id,session_id,condition,block,trial,phrase_id,timestamp,elapsed_from_first_input,event_type,text_before,text_after,inserted_character,deleted_character,is_practice")
        create("handflick_event_log.csv", header: "participant_id,session_id,condition,block,trial,phrase_id,region_id,finger,segment,flick_direction,contact_start_timestamp,recognition_timestamp,recognition_latency_ms,contact_distance,maximum_displacement,tracking_available_left,tracking_available_right,recognized_primitive,mapped_character,is_practice")
        create("hand_tracking.csv", header: "participant_id,session_id,block,trial,timestamp,chirality,joint_name,position_x,position_y,position_z,rotation_x,rotation_y,rotation_z,rotation_w,is_tracked,local_position_x,local_position_y,local_position_z")
        create("questionnaire.csv", header: "participant_id,session_id,condition,is_practice,mental_demand,physical_demand,temporal_demand,performance,effort,frustration,comfort,hand_fatigue,arm_fatigue,input_confidence,learnability,overall_satisfaction")
        create("final_preference.csv", header: "preference,comment")
    }
    func writeConfiguration(_ config: ExperimentConfig, order: [InputMethod], phraseSets: [String: String], practice: Bool) throws {
        struct Snapshot: Codable { let config: ExperimentConfig; let order: [InputMethod]; let phraseSets: [String: String]; let isPractice: Bool; let appVersion: String }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let data = try JSONEncoder.pretty.encode(Snapshot(config: config, order: order, phraseSets: phraseSets, isPractice: practice, appVersion: version))
        try data.write(to: directory.appendingPathComponent("experiment_config.json"), options: .atomic)
    }
    func logEvent(_ r: EventRecord) { append("event_log.csv", [r.context.participant,r.context.session,r.context.method.rawValue,"\(r.context.block)","\(r.context.trial)",r.context.phraseID,date(r.timestamp),r.firstInput.map { "\(r.timestamp.timeIntervalSince($0))" } ?? "",r.type.rawValue,r.before,r.after,r.inserted,r.deleted,"\(r.context.practice)"]) }
    func logTrial(_ r: TrialRecord) {
        let events = r.transcribed.count + r.backspaces.count
        let inputDuration = (r.firstInput != nil && r.lastInput != nil) ? r.lastInput!.timeIntervalSince(r.firstInput!) : nil
        let totalDuration = r.presented.map { r.done.timeIntervalSince($0) }
        append("trial_log.csv", [r.context.participant,r.context.session,r.context.method.rawValue,"\(r.context.order)",r.context.phraseSet,"\(r.context.block)","\(r.context.trial)",r.context.phraseID,r.target,r.transcribed,date(r.presented),date(r.firstInput),date(r.lastInput),date(r.done),inputDuration.map { String($0) } ?? "",totalDuration.map { String($0) } ?? "","\(events)","\(r.transcribed.filter { $0 != " " }.count)","\(r.backspaces.count)","\(r.transcribed.filter { $0 == " " }.count)","\(r.context.practice)"])
    }
    func logHandFlick(_ m: HandFlickMetadata, primitive: HandFlickPrimitive, output: String, context: LogContext) { append("handflick_event_log.csv", [context.participant,context.session,context.method.rawValue,"\(context.block)","\(context.trial)",context.phraseID,primitive.region.id,primitive.region.finger.rawValue,primitive.region.segment.rawValue,primitive.action.rawValue,date(m.contactStart),date(m.recognitionTime),"\(m.recognitionTime.timeIntervalSince(m.contactStart) * 1000)","\(m.contactDistance)","\(m.maximumDisplacement)","\(m.leftAvailable)","\(m.rightAvailable)","\(primitive.region.id):\(primitive.action.rawValue)",output,"\(context.practice)"]) }
    func logHandSample(_ sample: HandJointSample, context: LogContext, localPosition: SIMD3<Float>?) {
        let p = sample.worldTransform.translation; let q = simd_quatf(sample.worldTransform).vector; let local = localPosition ?? SIMD3<Float>(repeating: .nan)
        append("hand_tracking.csv", [context.participant,context.session,"\(context.block)","\(context.trial)","\(sample.timestamp)",sample.chirality,sample.joint,"\(p.x)","\(p.y)","\(p.z)","\(q.x)","\(q.y)","\(q.z)","\(q.w)","\(sample.isTracked)","\(local.x)","\(local.y)","\(local.z)"])
    }
    func logQuestionnaire(_ q: QuestionnaireResponse, method: InputMethod, practice: Bool) { append("questionnaire.csv", [participantID, sessionID, method.rawValue,"\(practice)","\(q.mental)","\(q.physical)","\(q.temporal)","\(q.performance)","\(q.effort)","\(q.frustration)","\(q.comfort)","\(q.handFatigue)","\(q.armFatigue)","\(q.confidence)","\(q.learnability)","\(q.satisfaction)"]) }
    func logPreference(_ preference: InputMethod, comment: String) { append("final_preference.csv", [preference.rawValue, comment]) }
    func flush() { for (name, rows) in buffers where !rows.isEmpty { let url = directory.appendingPathComponent(name); if let handle = try? FileHandle(forWritingTo: url) { try? handle.seekToEnd(); try? handle.write(rows.joined().data(using: .utf8)!); try? handle.close(); buffers[name] = [] } } }
    private func create(_ name: String, header: String) { FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: (header + "\n").data(using: .utf8)) }
    private func append(_ name: String, _ fields: [String]) { buffers[name, default: []].append(fields.map(csv).joined(separator: ",") + "\n") }
    private func csv(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
    private func date(_ date: Date?) -> String { date.map { ISO8601DateFormatter().string(from: $0) } ?? "" }
}
private extension JSONEncoder { static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder } }
private extension simd_float4x4 { var translation: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) } }
