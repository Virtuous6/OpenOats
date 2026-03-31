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
    private var sidecastPanel: OverlayPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var sidecastHostingView: NSHostingView<AnyView>?
    var defaults: UserDefaults = .standard

    /// If true, panel has no titlebar and accepts keyboard input.
    var borderless = false

    // Classic suggestions panel dimensions
    private static let classicWidth: CGFloat = 250
    private static let classicMinHeight: CGFloat = 100
    private static let classicMaxHeight: CGFloat = 400

    // Sidecast sidebar dimensions
    private static let sidecastDefaultWidth: CGFloat = 380
    private static let sidecastMinWidth: CGFloat = 300
    private static let sidecastMaxWidth: CGFloat = 550

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

    func showSidePanel<Content: View>(content: Content) {
        let erased = AnyView(content)

        if panel == nil {
            let screen = NSScreen.main ?? NSScreen.screens.first
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            let rect = NSRect(
                x: screenFrame.maxX - Self.classicWidth - 12,
                y: screenFrame.midY - Self.classicMaxHeight / 2,
                width: Self.classicWidth,
                height: Self.classicMaxHeight
            )
            let newPanel = OverlayPanel(contentRect: rect, defaults: defaults)
            newPanel.minSize = NSSize(width: Self.classicWidth, height: Self.classicMinHeight)
            newPanel.maxSize = NSSize(width: Self.classicWidth + 100, height: Self.classicMaxHeight)
            newPanel.setFrameAutosaveName("SuggestionSidePanel")
            panel = newPanel
        }

        if let hostingView {
            hostingView.rootView = erased
        } else {
            let newHostingView = NSHostingView(rootView: erased)
            hostingView = newHostingView
            panel?.contentView = newHostingView
        }
        panel?.orderFront(nil)
    }

    /// Show the full-height sidecast sidebar docked to the right edge.
    func showSidecastSidebar<Content: View>(content: Content) {
        let erased = AnyView(content)

        if sidecastPanel == nil {
            let screen = NSScreen.main ?? NSScreen.screens.first
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            // Full height, docked to right edge
            let rect = NSRect(
                x: screenFrame.maxX - Self.sidecastDefaultWidth,
                y: screenFrame.minY,
                width: Self.sidecastDefaultWidth,
                height: screenFrame.height
            )
            let newPanel = OverlayPanel(contentRect: rect, defaults: defaults)
            newPanel.minSize = NSSize(width: Self.sidecastMinWidth, height: 300)
            newPanel.maxSize = NSSize(width: Self.sidecastMaxWidth, height: screenFrame.height)
            newPanel.setFrameAutosaveName("SidecastSidebar")
            sidecastPanel = newPanel
        }

        if let sidecastHostingView {
            sidecastHostingView.rootView = erased
        } else {
            let newHostingView = NSHostingView(rootView: erased)
            sidecastHostingView = newHostingView
            sidecastPanel?.contentView = newHostingView
        }
        sidecastPanel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        sidecastPanel?.orderOut(nil)
    }

    func toggle<Content: View>(content: Content) {
        if panel?.isVisible == true {
            hide()
        } else {
            showSidePanel(content: content)
        }
    }

    func toggleSidecast<Content: View>(content: Content) {
        if sidecastPanel?.isVisible == true {
            sidecastPanel?.orderOut(nil)
        } else {
            showSidecastSidebar(content: content)
        }
    }

    var isVisible: Bool {
        panel?.isVisible == true || sidecastPanel?.isVisible == true
    }

    /// Hide after a delay (used for session end).
    func hideAfterDelay(seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            hide()
        }
    }

    /// Hide the standard close/minimize/zoom buttons on the panel.
    func hideWindowButtons() {
        panel?.standardWindowButton(.closeButton)?.isHidden = true
        panel?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel?.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
