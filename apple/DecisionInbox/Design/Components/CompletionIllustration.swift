import SwiftUI

/// One quiet close per local day and selected mailbox set. Opening the app or
/// revisiting the footer cannot repeatedly stage the same completion. Pending
/// arrivals reopen the mark immediately. This never changes completion truth.
struct CompletionIllustration: View {
    let verified: Bool
    let mailboxIDs: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.illustrationMotionEnabled) private var enabled
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("motion.closing.contexts.v1") private var contextsData = Data()
    @State private var phase = 0
    @State private var performing = false
    @State private var visible = false
    @State private var intersectsWindow = false

    private var context: String {
        let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        return "\(day)|\(mailboxIDs.sorted().joined(separator: "|"))"
    }
    private var canPresent: Bool { visible && intersectsWindow && enabled && scenePhase == .active }
    var body: some View {
        PaperIllustration(art: .closing, phase: verified ? phase : 0, motion: performing)
            .frame(width: 180, height: 96)
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.frame(in: .global).intersects(UIScreen.main.bounds)
            } action: { intersectsWindow = $0 }
            .onAppear { visible = true; settle() }
            .onDisappear { visible = false; performing = false }
            .onChange(of: verified) { settle() }
            .onChange(of: canPresent) { settle() }
            .onChange(of: mailboxIDs) { settle() }
            .task(id: performing) {
                guard performing else { return }
                do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
                phase = 2; performing = false
            }
    }
    private func settle() {
        guard verified else { phase = 0; performing = false; return }
        guard canPresent else { phase = 2; performing = false; return }
        var contexts = (try? JSONDecoder().decode([String].self, from: contextsData)) ?? []
        guard !contexts.contains(context), !mailboxIDs.isEmpty else {
            if !performing { phase = 2 }
            return
        }
        // Retain only this local day. Switching selected mailboxes and back
        // does not replay a context that already earned its mark.
        let day = String(context.split(separator: "|")[0]) + "|"
        contexts = contexts.filter { $0.hasPrefix(day) }
        contexts.append(context)
        if let encoded = try? JSONEncoder().encode(contexts) { contextsData = encoded }
        phase = reduceMotion ? 2 : 1
        performing = !reduceMotion
    }
}
