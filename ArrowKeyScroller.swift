import SwiftUI
import AppKit

/// Captures ⬅️/➡️ and scrolls the nearest NSScrollView horizontally.
/// Hold ⇧ (Shift) for a bigger step.
struct ArrowKeyScroller: NSViewRepresentable {
    var step: CGFloat = 160
    var fastStep: CGFloat = 480

    func makeCoordinator() -> Coordinator { Coordinator(step: step, fastStep: fastStep) }

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        let coord = context.coordinator   // capture the coordinator (class), not Context

        view.onBecomeActive = { v in
            // Find the nearest enclosing NSScrollView once we're in the hierarchy
            DispatchQueue.main.async {
                if let sv = v.enclosingScrollView {
                    coord.scrollView = sv
                } else {
                    var p = v.superview
                    while p != nil {
                        if let sv = p as? NSScrollView { coord.scrollView = sv; break }
                        p = p?.superview
                    }
                }
            }
        }

        view.onKey = { event in
            switch event.keyCode {
            case 123: // ←
                coord.scroll(isLeft: true, fast: event.modifierFlags.contains(.shift))
            case 124: // →
                coord.scroll(isLeft: false, fast: event.modifierFlags.contains(.shift))
            default:
                break
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        weak var scrollView: NSScrollView?
        let step: CGFloat
        let fastStep: CGFloat

        init(step: CGFloat, fastStep: CGFloat) {
            self.step = step
            self.fastStep = fastStep
        }

        func scroll(isLeft: Bool, fast: Bool) {
            guard let sv = scrollView, let doc = sv.documentView else { return }
            let cv = sv.contentView
            var origin = cv.bounds.origin
            let delta = (fast ? fastStep : step) * (isLeft ? -1 : 1)
            let maxX = max(0, doc.bounds.width - cv.bounds.width)
            origin.x = min(max(0, origin.x + delta), maxX)
            cv.setBoundsOrigin(origin)
            sv.reflectScrolledClipView(cv)
        }
    }
}

/// Simple NSView that tries to keep focus and forwards key events.
private final class KeyCatcherView: NSView {
    var onBecomeActive: (NSView) -> Void = { _ in }
    var onKey: (NSEvent) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
            self.onBecomeActive(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        onKey(event)
    }

    override func mouseEntered(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        super.mouseEntered(with: event)
    }
}
