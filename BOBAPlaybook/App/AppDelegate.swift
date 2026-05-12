//
//  AppDelegate.swift
//  BOBAPlaybook
//
//  Installs PortraitWindowController as the root on iOS 26+ to replace
//  the deprecated UIRequiresFullScreen Info.plist key.
//
//  Also routes external-display non-interactive scenes to
//  ExternalDisplaySceneDelegate (Personal Showcase second-screen
//  mode — see CollectionShowcaseView).
//

import UIKit
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {

    private var sceneObserver: Any?

    // Pre-iOS-26 orientation gate: consult OrientationManager.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationManager.shared.orientationMask
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if #available(iOS 26.0, *) {
            sceneObserver = NotificationCenter.default.addObserver(
                forName: UIScene.didActivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.installOrientationLock(for: notification)
            }
        }
        return true
    }

    /// Scene routing — external-display non-interactive role gets its
    /// own delegate (ExternalDisplaySceneDelegate) that mounts a
    /// UIHostingController hosting ExternalShowcaseRoot on the second
    /// screen. SwiftUI's WindowGroup handles the primary role.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        if role == .windowExternalDisplayNonInteractive {
            let config = UISceneConfiguration(
                name: "Showcase External Display",
                sessionRole: role
            )
            config.delegateClass = ExternalDisplaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: nil, sessionRole: role)
    }

    @available(iOS 26.0, *)
    private func installOrientationLock(for notification: Notification) {
        guard
            let windowScene = notification.object as? UIWindowScene,
            // Only the primary scene gets the orientation-lock wrap.
            // External-display non-interactive scenes have their own
            // hosting controller (ExternalShowcaseRoot) and must not
            // be wrapped — orientation doesn't apply to a TV anyway,
            // and wrapping the external UIHostingController would
            // break its rendering.
            windowScene.session.role == .windowApplication,
            let window = windowScene.windows.first,
            let rootVC = window.rootViewController,
            !(rootVC is PortraitWindowController)
        else { return }

        window.rootViewController = PortraitWindowController(rootVC)
    }
}

// MARK: - ExternalDisplaySceneDelegate
//
// Hosts ExternalShowcaseRoot (a SwiftUI view) on the external screen
// via UIHostingController. Tells ExternalDisplayManager.shared when
// connect/disconnect happens so the phone-side Showcase can switch
// to control-panel mode.
//
// Inlined into AppDelegate.swift rather than a standalone file to
// minimize PBXFileSystemSynchronizedRootGroup pickup risk (per
// memory `feedback_xcode_synchronized_groups.md`).
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let hosting = UIHostingController(rootView: ExternalShowcaseRoot())
        hosting.view.backgroundColor = .black
        window.rootViewController = hosting
        self.window = window
        window.isHidden = false
        Task { @MainActor in
            ExternalDisplayManager.shared.didConnect(window: window)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Task { @MainActor in
            ExternalDisplayManager.shared.didDisconnect()
        }
        window = nil
    }
}
