import CloudKit
import Observation
import SwiftUI
import UIKit

@MainActor @Observable final class ShareInbox {
    static let shared = ShareInbox()
    var pending: [CKShare.Metadata] = []
}

final class POCAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = POCSceneDelegate.self
        return configuration
    }
}

final class POCSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata { ShareInbox.shared.pending.append(metadata) }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareInbox.shared.pending.append(metadata)
    }
}

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let changed: () -> Void
    let failure: (Error) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(changed: changed, failure: failure) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let changed: () -> Void; let failure: (Error) -> Void
        init(changed: @escaping () -> Void, failure: @escaping (Error) -> Void) { self.changed = changed; self.failure = failure }
        func itemTitle(for csc: UICloudSharingController) -> String? { "Lokasi peserta POC C67" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { failure(error) }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { changed() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { changed() }
    }
}
