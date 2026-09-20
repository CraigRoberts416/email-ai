import SwiftUI

/// Compact presentation only. Closing it does not clear records or cancel work.
struct UnsubscribeTray: View {
    let runs: [UnsubscribeRun]
    var onOpenLog: () -> Void = {}
    var onClose: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicType

    private var active: Int { runs.filter { !$0.isTerminal }.count }
    private var attention: Int { runs.filter { $0.needsAttention && $0.userReportedComplete != true }.count }
    private var current: UnsubscribeRun? { runs.first(where: { $0.needsAttention }) ?? runs.first }
    private var title: String {
        if attention > 0 { return "\(attention) \(attention == 1 ? "task needs" : "tasks need") you" }
        if active > 0 { return "\(active) unsubscribe \(active == 1 ? "attempt" : "attempts") working" }
        return runs.count == 1 ? (runs.first?.title ?? "Activity") : "\(runs.count) unsubscribe receipts"
    }
    private var compactTitle: String {
        if attention > 0 { return "\(attention) \(attention == 1 ? "needs" : "need") you" }
        if active > 0 { return "\(active) working" }
        return "\(runs.count) \(runs.count == 1 ? "result" : "results")"
    }
    private var accessibilitySummary: String {
        [title, current?.senderName].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Button(action: onOpenLog) {
                HStack(spacing: Space.md) {
                    Image(systemName: attention > 0 ? "person.crop.circle.badge.exclamationmark" : "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dynamicType.isAccessibilitySize ? compactTitle : title).typeStyle(Style.navAction)
                        if !dynamicType.isAccessibilitySize, let current {
                            Text(current.senderName ?? "View activity")
                                .typeStyle(Style.bodySmall).foregroundStyle(Ink.onInverseSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up").font(.system(size: 12))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Opens task details and available actions")
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide activity summary")
            .accessibilityHint("Work continues. Find it again in Activity.")
        }
        .foregroundStyle(Ink.onSheet)
        .padding(.leading, Space.lg)
        .padding(.trailing, 4)
        .padding(.vertical, Space.sm)
        .background(Ink.inverse, in: RoundedRectangle(cornerRadius: Corner.xl, style: .continuous))
        .frame(maxWidth: 520)
    }
}

extension UnsubscribeRun {
    var sender: Sender? {
        guard let senderName else { return nil }
        return Sender(name: senderName, address: actionURL?.host ?? messageId, kind: .brand, logoURL: nil)
    }
}
