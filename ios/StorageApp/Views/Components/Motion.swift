import SwiftUI
import UIKit

// Reduce Motion support. With the iPhone's Reduce Motion setting off, these
// return the animation or transition unchanged, so the app looks exactly as
// designed. With it on, springs, bounces, slides and zooms become a short
// cross-fade, which is what Apple's Reduced Motion criteria ask for.

extension Animation {
    /// `self`, or a brief ease with no bounce when Reduce Motion is on.
    var motionSafe: Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeInOut(duration: 0.2) : self
    }
}

extension AnyTransition {
    /// `self`, or a plain fade when Reduce Motion is on.
    var motionSafe: AnyTransition {
        UIAccessibility.isReduceMotionEnabled ? .opacity : self
    }
}
