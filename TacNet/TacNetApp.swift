import SwiftUI
import UIKit

// AppDelegate is required to handle the background URLSession callback that iOS
// delivers when the model download completes while the app is not in the foreground.
// Without this, iOS cannot inform the app that the download finished, and the system
// cannot update its background-app snapshot.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Only handle our model-download background session.
        guard identifier == URLSessionDownloadClient.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        // Accessing .shared re-creates the URLSession with the same identifier,
        // reconnecting it to the in-flight background download task.
        URLSessionDownloadClient.shared.handleBackgroundSessionEvents(completionHandler: completionHandler)
    }
}

@main
struct TacNetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
