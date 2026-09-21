import SwiftUI

@main
struct DecisionInboxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-sampleMotion") {
                MotionGallery()
            } else {
                RootView()
            }
            #else
            RootView()
            #endif
        }
    }
}
