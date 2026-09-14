import SwiftUI
import UIKit

/// The whole tactile vocabulary of the product: four cues, named by what they
/// mean rather than by how hard they hit.
///
/// Naming by meaning is the load-bearing decision. A call site can ask for
/// "this committed" but cannot ask for "a stronger one", so the vocabulary
/// cannot inflate one feature at a time until every event buzzes.
///
/// **There is deliberately no `.success` cue anywhere in this product.** Every
/// success in Decision Inbox is either visible — the post leaves the feed, the
/// bookmark fills — or reported by a receipt that stays on screen for 6–8
/// seconds. A success buzz on the expected outcome is the precise mechanism by
/// which an app teaches people to ignore its haptics.
///
/// The silences are specified as strictly as the sounds; see `Haptics` call
/// sites and the block comment at the bottom of this file.
@MainActor
enum Haptics {
    /// A preference of its own. Reduce Motion is a *different* preference
    /// answering a different need and must not gate this — a vestibular
    /// sensitivity is not a reason to remove touch feedback. iOS already
    /// honours Settings ▸ Sounds & Haptics ▸ System Haptics underneath every
    /// generator below, so this switch sits on top of that, never around it.
    @AppStorage("haptics.enabled") static var enabled = true

    // Declared once and held, because constructing a generator at the moment
    // of use is exactly when it is too late to be warm.
    private static let selection = UISelectionFeedbackGenerator()
    private static let rigid     = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft      = UIImpactFeedbackGenerator(style: .soft)
    private static let light     = UIImpactFeedbackGenerator(style: .light)
    private static let notice    = UINotificationFeedbackGenerator()

    /// Call on a gesture's FIRST sample, never on view appear — a prepared
    /// generator holds the Taptic Engine warm and costs power. A feed of forty
    /// posts each preparing on appear would hold it warm for the whole session.
    static func prepare() { rigid.prepare() }

    /// "Let go now and the outcome changes." The threshold is under the finger
    /// and therefore invisible; touch is the only honest channel for it.
    ///
    /// Fires on *disarm* as well as arm, or a user who pulls back short of the
    /// line gets no confirmation that they escaped the commit.
    static func threshold() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.65)
    }

    /// "That state now holds." Filing, saving, reversing.
    ///
    /// One cue for both directions of a toggle — save and unsave are one
    /// decision made twice, not two different events.
    static func commit() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.75)
    }

    /// "The view is about to change wholesale." The lightest cue in the set,
    /// reserved for the heaviest visual event — the inverse of the intuition
    /// that a big change deserves a big buzz.
    static func announce() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.5)
    }

    /// "This did not work and you cannot see that." The ONLY notification-class
    /// cue in the product, and the only cue allowed to reach a user who has
    /// navigated away from the thing that failed.
    ///
    /// Suppressed when the app is not frontmost: a buzz in a pocket reports
    /// something the user cannot go and look at.
    static func failed() {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        notice.notificationOccurred(.error)
    }

    /// `UISelectionFeedbackGenerator` is declared and, in the current feature
    /// set, never called. It is kept because a future detented control — a
    /// snooze-time picker, a per-sender frequency stepper — is the correct home
    /// for it. If none ships, delete it; do not find a use for it.
    ///
    /// A flicked carousel does **not** earn it: continuous, frequent, and the
    /// page dots already carry the state.
    static func detent() {
        guard enabled else { return }
        selection.selectionChanged()
    }
}

// MARK: - The silences
//
// This half of the vocabulary matters more than the half above. Each entry is
// a decision that has already been made once, so it does not get remade by
// whoever next touches the call site.
//
//   New posts arriving, any SSE event, any interpretation completing
//       Not user-caused, and unbounded in frequency. An event is not a frame,
//       and arrival is not the user's action.
//   Every chunk of streamed text
//       Same rule, stated at its limit: never bind feedback to a token.
//   Tapping a post to open a thread
//       The entire screen changes. A cue on every navigation is the canonical
//       over-buzz.
//   Every button press, every tab change, every scroll
//       Press feedback is visual (PostPressStyle / TapStyle in Controls.swift).
//   Reaching the end of the feed
//       A finite inbox hits "That's the lot" daily. Celebrating a routine
//       state is the worst available use of the budget.
//   Pull-to-refresh release, and refresh success
//       The threshold cue already fired at the decision point. A second cue
//       re-reports one decision, and success is the common case.
//   Tapping Send
//       The composer dismisses and a receipt appears — both visible. More
//       importantly: NOTHING HAS BEEN COMMITTED. An impact at tap would assert
//       commitment during an 8-second window in which the send has not
//       happened. This is a truth problem, not a taste problem.
//   Send succeeding
//       Expected case; the receipt says so.
//   Discuss — question sent, answer arrives, answer fails
//       The user is looking at the screen and the text is the feedback.
//   Context-menu long press
//       The system fires its own lift haptic. Ours would double it.
//   Carousel page change
//       Continuous and frequent; the page dots carry it.
//   Sheet present / dismiss, navigation push / pop
//       System-owned.
//   An attachment exceeding 25 MB
//       The border thickens and the copy explains. A warning buzz on a field
//       the user is still filling is punitive.
//   A POSSIBLE SCAM kicker appearing
//       Deliberate, and the most important silence here. The classification is
//       a probabilistic model output. A warning haptic converts an uncertain
//       recognition into a confident tactile verdict, which the system cannot
//       support. It stays typographic, where its hedging stays visible.
//
// Mixing rules:
//   1. One cue per decision. A swipe that commits an archive fires the
//      threshold cue and nothing at release — the commit cue is suppressed
//      when the action originated from a swipe.
//   2. Cancellation never fires a commit-class cue.
//   3. Never queue. If the originating view is gone when an async result
//      lands, drop the cue. `failed()` is the one exception and carries its own
//      foreground guard.
//   4. Generators are prepared on a gesture's first sample, not on view appear.
