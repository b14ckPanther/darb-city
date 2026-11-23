import SwiftUI
import UIKit

/// Keeps the swipe back from the screen's edge working on a page that draws its own back button.
/// Hiding the system's back button would otherwise switch that swipe off.
/// It also says when the page starts to leave (a tap on back, a swipe from the edge, a pull down) and when it is
/// back in front, so the page can change what it shows before it moves.
struct KeepBackSwipe: UIViewControllerRepresentable {
    var leaving: () -> Void = {}
    var returned: () -> Void = {}
    func makeUIViewController(context: Context) -> Keeper { Keeper() }
    func updateUIViewController(_ controller: Keeper, context: Context) {
        controller.leaving = leaving
        controller.returned = returned
    }

    final class Keeper: UIViewController, UIGestureRecognizerDelegate {
        var leaving: () -> Void = {}
        var returned: () -> Void = {}
        private var seen = false
        private weak var swipe: UIGestureRecognizer?
        private weak var before: UIGestureRecognizerDelegate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if seen { returned() }
            seen = true
            guard swipe == nil, let recognizer = navigationController?.interactivePopGestureRecognizer else { return }
            swipe = recognizer
            before = recognizer.delegate
            recognizer.delegate = self
            recognizer.isEnabled = true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            // the page is gone and home is fully back: the end of a tap on back
            Perf.shown("back")
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // only when the page itself is going away; a page pushed on top of it leaves it as it is
            if isLeavingTheStack { leaving() }
            // hand the swipe back as it was found
            if let swipe, swipe.delegate === self { swipe.delegate = before }
            swipe = nil
        }

        /// The page is being popped (by the back button, a swipe from the edge or a pull down), not covered by another page.
        private var isLeavingTheStack: Bool {
            guard let nav = navigationController else { return true }
            var page: UIViewController = self
            while let parent = page.parent, parent !== nav { page = parent }
            return page.isMovingFromParent || !nav.viewControllers.contains(page)
        }

        /// Only when there is a screen to go back to.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
