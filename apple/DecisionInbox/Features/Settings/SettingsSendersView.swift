import SwiftUI

struct SettingsSendersView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var inspecting = false

    var body: some View {
        SettingsScreen(title: "Senders", onBack: { dismiss() }) {
            SettingsGroup("UNSUBSCRIBE ACTIVITY · \(store.unsubscribeRuns.count)",
                caption: "Attempts and their evidence. Working, request sent, needs you and sender confirmed remain distinct.")
            Rule()
            if store.unsubscribeRuns.isEmpty {
                SettingsParagraph("Unsubscribe attempts will appear here. Closing their progress card keeps this history available.")
            }
            ForEach(store.unsubscribeRuns) { run in
                ListRow(title: run.senderName ?? "Sender", subtitle: run.title,
                    action: { selectedID = run.id; inspecting = true },
                    leading: { Image(systemName: run.needsAttention ? "person.crop.circle" : "clock.arrow.circlepath") },
                    trailing: { Image(systemName: "chevron.right").foregroundStyle(Ink.secondary) })
                Rule()
            }
            SettingsGroup("SCOPE")
            SettingsParagraph("An unsubscribe asks the sender to remove you. It does not block future mail locally. Request sent means transmission; Sender confirmed requires a confirmation from the sender’s page. Receipts do not monitor future mail.")
        }
        .sheet(isPresented: $inspecting) { UnsubscribeRunLog(focusID: selectedID) }
    }
}
