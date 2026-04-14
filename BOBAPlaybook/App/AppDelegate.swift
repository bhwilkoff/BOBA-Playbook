//
//  AppDelegate.swift
//  BOBAPlaybook
//
//  Installs PortraitWindowController as the root on iOS 26+ to replace
//  the deprecated UIRequiresFullScreen Info.plist key.
//

import UIKit

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

    @available(iOS 26.0, *)
    private func installOrientationLock(for notification: Notification) {
        guard
            let windowScene = notification.object as? UIWindowScene,
            let window = windowScene.windows.first,
            let rootVC = window.rootViewController,
            !(rootVC is PortraitWindowController)
        else { return }

        window.rootViewController = PortraitWindowController(rootVC)
    }
}
