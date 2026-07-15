import SwiftUI

@main
struct StarCatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
                .statusBarHidden(true)
        }
    }
}
