//
//  HandFlickApp.swift
//  HandFlick
//
//  Created by 一居和毅 on 2026/08/20.
//

import SwiftUI

@main
struct HandFlickApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        .persistentSystemOverlays(.hidden)
     }
}
