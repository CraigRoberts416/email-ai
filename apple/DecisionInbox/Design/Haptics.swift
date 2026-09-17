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
    ///
    /// Both generators the swipe can reach, not just the first one. It warmed
    /// only `rigid`, which is the threshold cue — so the gesture's *second*
    /// half, the commit, fired from a cold generator every time. Preparing one
    /// of the two is the failure this function exists to prevent, applied to
    /// half the gesture.
    static func prepare() {
        rigid.prepare()
        soft.prepare()
    }

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

    /// "An outcome needs looking at, and you may not be looking."
    ///
    /// This was `failed()`, and the name was doing damage at one of its call
    /// sites. An unconfirmed send is NOT a refusal — the request never came
    /// back, the mail may well have gone, and `FeedStore` says exactly that in
    /// its own comment before firing a definitive failure cue. Asserting
    /// failure about an unknown outcome is the same class of error as
    /// asserting success about a pending one, which this system already
    /// forbids everywhere else.
    ///
    /// One cue covers refusal and uncertainty on purpose. Both need the same
    /// thing from the user — come back and read the receipt — and a second
    /// notification-class cue would have to be discriminable from this one to
    /// be worth anything, which two error buzzes are not. The receipt carries
    /// the difference in words, where a hedge can survive.
    ///
    /// The ONLY notification-class cue in the product, and the only cue
    /// allowed to reach a user who has navigated away. Suppressed when the app
    /// is not frontmost: a buzz in a pocket reports something they cannot go
    /// and look at.
    static func needsYou() {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        notice.notificationOccurred(.error)
    }

    /// One tick per item crossed in a detented control.
    ///
    /// Its call site is the reaction picker, which is the case this was held
    /// open for: discrete stops, one live at a time, and — the part that
    /// actually earns the cue — the finger is covering the thing it is
    /// choosing, so touch is the only channel that can report the change.
    ///
    /// A flicked carousel still does **not** earn it: continuous, frequent,
    /// and the page dots already carry the state.
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
//   Tapping Unsubscribe
//       Same rule as Send, and it was being broken. Unsubscribe is a network
//       operation that opens a tray and can fail minutes later; a commit cue
//       at tap asserts "that state now holds" about work that has not started.
//       The tray appearing is the acknowledgement, and `needsYou()` fires if
//       it fails. Save and Archive keep their commit cue because they are
//       local, immediate and already true when the finger lifts.
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
//   4. Generators are prepared on a gesture's first sample, not on view appear,
//      and every generator that gesture can reach is prepared together.
//   5. ONE owner per event. The layer that owns the state owns the cue. A
//      reaction fired twice — `commit()` from the picker and `detent()` from
//      the store — because both layers believed they owned it, and the user
//      felt two different cues for one decision. A view may not emit a cue for
//      a state change it delegates to the store.
//   6. A cue may not out-claim the work. Local and immediate earns `commit()`;
//      anything that can still fail earns silence at the point of intent and
//      `needsYou()` if it does fail.
