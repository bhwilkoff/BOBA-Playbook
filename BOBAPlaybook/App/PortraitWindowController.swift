//
//  PortraitWindowController.swift
//  BOBAPlaybook
//
//  Wraps the SwiftUI root hosting controller to declare portrait-only
//  orientation lock via the iOS 26 replacement for UIRequiresFullScreen.
//

import UIKit

@available(iOS 26.0, *)
final class PortraitWindowController: UIViewController {

    private let content: UIViewController

    init(_ content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Restrict to portrait on all iOS versions (works alongside UISupportedInterfaceOrientations
    // declaring all four orientations to satisfy App Store validation).
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // iOS 26 replacement for UIRequiresFullScreen
    @available(iOS 26.0, *)
    override var prefersInterfaceOrientationLocked: Bool { true }

    // Forward orientation lock decisions to the SwiftUI hosting controller (iOS 26+)
    @available(iOS 26.0, *)
    override var childForInterfaceOrientationLock: UIViewController? { content }

    // Forward status bar appearance to the hosted content
    override var childForStatusBarStyle: UIViewController? { content }
    override var childForStatusBarHidden: UIViewController? { content }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(content.view)
        content.didMove(toParent: self)
    }
}
