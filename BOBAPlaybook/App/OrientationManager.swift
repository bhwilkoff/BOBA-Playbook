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
    private init() {
        orientationMask = OrientationManager.defaultMask
    }

    /// Per DESIGN.md §6.6, iPad ships first-class with landscape
    /// available everywhere; iPhone stays portrait-only as the
    /// default. Practice still forces landscape via `lockLandscape()`
    /// on both idioms.
    private static var defaultMask: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .allButUpsideDown : .portrait
    }

    private(set) var orientationMask: UIInterfaceOrientationMask

    func lockLandscape() {
        orientationMask = [.landscapeLeft, .landscapeRight]
        applyOrientationChange()
    }

    /// Allow landscape without forcing rotation — user rotates manually
    func allowLandscape() {
        orientationMask = .allButUpsideDown
        // Only update supported orientations, don't force geometry change
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.first?.rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    /// Restore the device-default mask (iPhone: portrait, iPad: all-
    /// but-upside-down). Named `lockPortrait` for backward-compat with
    /// PracticeView's onDisappear; semantically it's "restore default."
    func lockPortrait() {
        orientationMask = OrientationManager.defaultMask
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
