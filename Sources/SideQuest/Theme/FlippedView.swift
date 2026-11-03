import AppKit

/// Uses top-to-bottom coordinates for scrollable journal and tracker content.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
