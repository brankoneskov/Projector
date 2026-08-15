//
//  ArrowKeyHandler.swift
//  Projector
//
//  Created by Branko Neskov on 02/11/2025.
//
import SwiftUI
import AppKit

/// Captures ⬅️/➡️ and calls your closures. Use this when there's nothing to scroll.
struct ArrowKeyHandler: NSViewRepresentable {
    var onLeft: () -> Void
    var onRight: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = SimpleKeyView()
        v.onLeft = onLeft
        v.onRight = onRight
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SimpleKeyView: NSView {
    var onLeft: () -> Void = {}
    var onRight: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onLeft()   // ←
        case 124: onRight()  // →
        default: super.keyDown(with: event)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        super.mouseEntered(with: event)
    }
}

