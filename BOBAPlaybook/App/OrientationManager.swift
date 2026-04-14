//
//  OrientationManager.swift
//  BOBAPlaybook
//
//  Singleton that lets individual views request orientation changes.
//  PracticeView calls lockLandscape() on appear and lockPortrait() on disappear.
//  PortraitWindowController and AppDelegate consult this singleton to decide
//  which orientations to allow at any moment.
//

import UIKit

@MainActor
final class OrientationManager {
    static let shared = OrientationManager()
    private init() {}

    private(set) var orientationMask: UIInterfaceOrientationMask = .portrait

    func lockLandscape() {
        orientationMask = [.landscapeLeft, .landscapeRight]
        applyOrientationChange()
    }

    func lockPortrait() {
        orientationMask = .portrait
        applyOrientationChange()
    }

    private func applyOrientationChange() {
        // iOS 26+: ask the window scene to rotate
        if #available(iOS 16.0, *) {
            let scenes = UIApplication.shared.connectedScenes
            for scene in scenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: orientationMask
                )
                windowScene.requestGeometryUpdate(geometryPreferences) { error in
                    // Ignore errors — the system may reject landscape on iPad multi-window etc.
                    _ = error
                }
                // Tell the root view controller to re-query supported orientations
                windowScene.windows.first?.rootViewController?
                    .setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}
