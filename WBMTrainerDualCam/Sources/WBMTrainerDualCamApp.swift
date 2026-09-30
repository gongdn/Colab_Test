import SwiftUI

@main
struct WBMTrainerDualCamApp: App {
    @StateObject private var manager = DualCameraManager()

    var body: some Scene {
        WindowGroup {
            DualCameraView(manager: manager)
                .onAppear { manager.start() }
                .onDisappear { manager.stop() }
        }
    }
}
