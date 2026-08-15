//
// WindowFramePersistence.swift
// Projector
//

import SwiftUI
import AppKit
import ObjectiveC

// Calls onResolve(window) when the SwiftUI view is attached to a window.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let win = view?.window {
                onResolve(win)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowFrameBinder {
    private weak var window: NSWindow?
    private let key: String
    private var observers: [NSObjectProtocol] = []

    init(window: NSWindow, key: String) {
        self.window = window
        self.key = key
    }

    func attach() {
        guard let win = window else { return }
        restoreFrame(on: win)
        let center = NotificationCenter.default
        let save: (Notification) -> Void = { [weak self] _ in self?.saveFrame() }
        observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: win, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: win, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: win, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main, using: save))
    }

    private func restoreFrame(on win: NSWindow) {
        let d = UserDefaults.standard
        guard
            d.object(forKey: "\(key).w") != nil,
            d.object(forKey: "\(key).h") != nil,
            d.object(forKey: "\(key).x") != nil,
            d.object(forKey: "\(key).y") != nil
        else { return }

        var f = win.frame
        f.size.width  = max(400, d.double(forKey: "\(key).w"))
        f.size.height = max(300, d.double(forKey: "\(key).h"))
        f.origin.x    = d.double(forKey: "\(key).x")
        f.origin.y    = d.double(forKey: "\(key).y")

        win.setFrame(f, display: true)
        DispatchQueue.main.async {
            win.setFrame(f, display: true)
        }
    }

    private func saveFrame() {
        guard let f = window?.frame else { return }
        let d = UserDefaults.standard
        d.set(f.size.width,  forKey: "\(key).w")
        d.set(f.size.height, forKey: "\(key).h")
        d.set(f.origin.x,    forKey: "\(key).x")
        d.set(f.origin.y,    forKey: "\(key).y")
    }

    private static var assocKey: UInt8 = 0

    static func attach(to window: NSWindow, key: String) {
        if let existing = objc_getAssociatedObject(window, &assocKey) as? WindowFrameBinder {
            existing.attach()
            return
        }
        let binder = WindowFrameBinder(window: window, key: key)
        objc_setAssociatedObject(window, &assocKey, binder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        binder.attach()
    }
}

private struct WindowFramePersistence: ViewModifier {
    let key: String
    func body(content: Content) -> some View {
        content.background(
            WindowAccessor { win in
                WindowFrameBinder.attach(to: win, key: key)
            }
        )
    }
}

extension View {
    /// Persists/restores the NSWindow frame using the given unique key.
    func persistWindowFrame(_ key: String) -> some View {
        modifier(WindowFramePersistence(key: key))
    }
}
