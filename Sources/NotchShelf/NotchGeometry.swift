import AppKit

/// Position of the notch on screen. Without a notch, falls back to a rect of
/// menu bar height centred on the top edge.
struct NotchGeometry {
    let screen: NSScreen
    /// The notch rect in screen coordinates.
    let notchRect: CGRect
    /// Menu bar height.
    let barHeight: CGFloat

    static func current() -> NotchGeometry? {
        guard let screen = NSScreen.main else { return nil }
        let frame = screen.frame
        let barHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)

        let notchRect: CGRect
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            notchRect = CGRect(x: left.maxX,
                               y: frame.maxY - barHeight,
                               width: right.minX - left.maxX,
                               height: barHeight)
        } else {
            let width: CGFloat = 180
            notchRect = CGRect(x: frame.midX - width / 2,
                               y: frame.maxY - barHeight,
                               width: width,
                               height: barHeight)
        }
        return NotchGeometry(screen: screen, notchRect: notchRect, barHeight: barHeight)
    }

    /// Hover zone that opens the panel: the notch, and barely more than it.
    ///
    /// It used to be 32 points wider than the notch and hang ten points below
    /// it — 211 × 46 against a notch of 179 × 32 — on the theory that a generous
    /// zone is easier to hit. It is, and it also catches everything that was
    /// never aimed at it: a cursor thrown up at the menu bar, a swipe up, a
    /// hand crossing the top of the screen on its way somewhere else. Measured
    /// over a day, 374 opens, and 37 % of them were over inside three seconds
    /// because nobody had asked for them.
    ///
    /// Six points a side is enough to forgive the aim of a hand moving fast.
    /// Nothing below the notch at all: the first row of tabs starts there.
    var triggerRect: CGRect {
        let sideMargin: CGFloat = 6
        // The cursor comes to rest exactly on the top edge of the screen, and
        // CGRect.contains excludes its maximum edge, so a zone ending at the
        // screen top never matched. It has to reach past it.
        return CGRect(x: notchRect.minX - sideMargin,
                      y: notchRect.minY,
                      width: notchRect.width + sideMargin * 2,
                      height: notchRect.height + 4)
    }

    /// Clicks are caught on the notch itself, not on the wider hover zone:
    /// the status icons sit right next to it and must stay clickable.
    var clickRect: CGRect { notchRect }

    /// The zone that shuts an open panel: the notch, and nothing beside it.
    ///
    /// Still not `triggerRect`, even now that the two are nearly the same shape.
    /// Opening forgives a few points of aim; closing forgives none, because the
    /// status icons sit immediately to either side and a panel that folds away
    /// when the cursor passes one of them is a panel that cannot be left open.
    var closeRect: CGRect {
        CGRect(x: notchRect.minX,
               y: notchRect.minY,
               width: notchRect.width,
               // Past the top of the screen, where the cursor comes to rest:
               // `contains` excludes a rect's maximum edge.
               height: notchRect.height + 4)
    }

    /// Window frame: the box holding both the notch strip and the open panel.
    func windowFrame(expandedSize: CGSize) -> CGRect {
        let width = max(expandedSize.width, notchRect.width)
        let height = notchRect.height + expandedSize.height
        return CGRect(x: notchRect.midX - width / 2,
                      y: screen.frame.maxY - height,
                      width: width,
                      height: height)
    }
}
