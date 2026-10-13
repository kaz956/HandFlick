//
//  ImmersiveView.swift
//  HandFlick
//
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var inputOverlay = HandFlickOverlay()

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)

                // Put skybox here.  See example in World project available at
                // https://developer.apple.com/
            }
            inputOverlay.install(in: content)
        }
        .task {
            appModel.handTracker.onGeometry = { geometry, activeRegion, state in
                inputOverlay.update(geometry: geometry, activeRegion: activeRegion, state: state)
            }
            await appModel.handTracker.start(config: appModel.experiment.config.handFlickConfig)
        }
        .onDisappear { inputOverlay.hide(); appModel.handTracker.onGeometry = nil; appModel.handTracker.stop() }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
