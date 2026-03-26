import AppKit
import SwiftUI

/// A floating NSPanel that is invisible to screen sharing.
class OverlayPanel: NSPanel {
    init(contentRect: NSRect, defaults: UserDefaults = .standard) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        let hidden = defaults.object(forKey: "hideFromScreenShare") == nil
            ? true
            : defaults.bool(forKey: "hideFromScreenShare")
        sharingType = hidden ? .none : .readOnly
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Remember position
        setFrameAutosaveName("OverlayPanel")
    }
}

/// A floating panel that CAN become key window (for text input).
final class KeyableOverlayPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Manages the overlay panel lifecycle.
@MainActor
final class OverlayManager: ObservableObject {
    private var panel: OverlayPanel?
    var defaults: UserDefaults = .standard

    /// If true, panel has no titlebar and accepts keyboard input.
    var borderless = false

    func show<Content: View>(content: Content) {
        if panel == nil {
            let rect = NSRect(x: 100, y: 100, width: 400, height: 300)
            if borderless {
                let tallRect = NSRect(x: rect.origin.x, y: rect.origin.y, width: 400, height: 400)
                let p = KeyableOverlayPanel(contentRect: tallRect, defaults: defaults)
                p.styleMask = [.resizable]
                p.level = .normal
                p.isFloatingPanel = false
                p.hasShadow = false  // SwiftUI view handles its own shadow
                p.setFrameAutosaveName("NotepadPanel")
                panel = p
            } else {
                panel = OverlayPanel(contentRect: rect, defaults: defaults)
            }
        }

        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = .intrinsicContentSize
        panel?.contentView = hostingView
        panel?.orderFront(nil)
        if borderless {
            panel?.makeKey()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle<Content: View>(content: Content) {
        if panel?.isVisible == true {
            hide()
        } else {
            show(content: content)
        }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    /// Hide the standard close/minimize/zoom buttons on the panel.
    func hideWindowButtons() {
        panel?.standardWindowButton(.closeButton)?.isHidden = true
        panel?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel?.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
