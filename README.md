# HandFlick research experiment for visionOS

This visionOS app compares three assigned conditions: **HandFlick**, **Default Keyboard — Direct Touch**, and **Default Keyboard — Gaze + Pinch**. The two default-keyboard conditions use the OS keyboard presented by a standard SwiftUI `TextField`; no custom baseline keyboard or private API is used.

## Architecture

- `ExperimentManager.swift` owns counterbalancing, phrase scheduling, trial flow, text-change classification, and experiment state.
- `HandFlickTracking.swift` uses public ARKit Hand Tracking. It constructs 12 finger-segment line geometries, maintains a left-hand-relative coordinate basis, uses contact/release hysteresis, and emits a `HandFlickPrimitive` rather than a character.
- `ExperimentModels.swift` keeps the recognition primitive, layout/mapping, thresholds, and experiment parameters separate. The default English key entries deliberately have empty direction maps: populate `characterByAction` only after confirming the deployed Vision Pro system-flick layout during a pilot. This avoids silently assuming a layout.
- `ExperimentLogger.swift` creates a new Documents/`HandFlickData` session directory and buffers append-only CSV output. It flushes after every trial and condition questionnaire.
- `ExperimentViews.swift` contains setup, instruction, transcription, breaks, questionnaires, and completion UI.

## Configuration and phrases

`ExperimentConfig` centralizes block count, trial count, break policy, debug mode, and all HandFlick thresholds. `Phrases.json` is the editable resource that supplies phrase IDs and A/B/C pools. The setup screen lets the experimenter overwrite the participant-ID counterbalanced condition order and phrase-set assignment.

`FlickKeyMapping.characterByAction` is preconfigured for the iPhone Japanese 12-key keyboard's English mode: center, left, up, right, down. On the left-hand input surface, these correspond to center, backward (wrist), radial (index side), forward (fingertip), ulnar (little-finger side). The mapping remains a separate configuration layer, so it can be changed after a pilot. Space and backspace primitives and the eight letter-group region assignments are also configuration values.

## Data

Each session gets a unique directory containing `trial_log.csv`, `event_log.csv`, `handflick_event_log.csv`, `hand_tracking.csv`, `questionnaire.csv`, `final_preference.csv`, and `experiment_config.json`. Timestamps use wall-clock ISO-8601 values; elapsed durations are written alongside them for analysis. Target text, final transcription, and the full event sequence are retained so WPM, CER/MSD, corrected/uncorrected error, and KSPC can be computed post hoc.

## Permissions and limitations

The app requires the Hand Tracking usage permission for HandFlick. ARKit tracking loss cancels the active gesture and records tracking-loss/recovery events. The OS does not publicly expose the direct-touch versus gaze-and-pinch source of system-keyboard events; the assigned condition, instructions, and text changes are logged instead. The app requests lowercase ASCII entry and disables autocorrection where SwiftUI exposes it, but visionOS may retain system-level prediction or keyboard behavior that the app cannot control. Run on Vision Pro / a target SDK that exposes `HandTrackingProvider`; no private APIs are used.
