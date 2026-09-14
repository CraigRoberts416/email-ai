import SwiftUI

/// `02 · Settings · Feed`.
///
/// One thing on this screen changes the feed, and it is the only thing on this
/// screen: which mailboxes feed it. `FeedStore.messages()` filters on exactly
/// this set, so a mailbox switched off here stops appearing the moment you go
/// back — which is the test every control in the product has to pass.
///
/// What is *not* here, and why: order, day-grouping, the pulled quote, density
/// and archive-after-acting were all drawn as controls. None of them is
/// readable by anything in the app today, so none of them is offered. The
/// paragraph at the bottom says so rather than leaving the absence to be
/// discovered.
struct SettingsFeedView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var filtering = false

    /// Past five mailboxes the per-row toggles become a sheet with search and
    /// multi-select — the threshold the scale board sets.
    private var isLarge: Bool { store.mailboxes.count > 5 }

    var body: some View {
        SettingsScreen(title: "Feed", onBack: { dismiss() }) {
            if store.mailboxes.count > 1 {
                SettingsGroup(
                    "MAILBOXES IN THIS FEED",
                    caption: "Leaving one out hides its mail here. The mailbox stays connected, and nothing is deleted."
                )
                Rule()

                if isLarge {
                    SettingsLink(title: "Choose mailboxes", value: countLabel) {
                        filtering = true
                    }
                    Rule()
                } else {
                    ForEach(store.mailboxes) { mailbox in
                        SettingsToggle(
                            title: mailbox.address,
                            subtitle: mailbox.stateLabel,
                            isOn: Binding(
                                get: { store.mailbox(mailbox.id)?.includeInUnifiedFeed ?? true },
                                set: { store.setIncluded(mailbox.id, $0) }
                            )
                        )
                        Rule()
                    }
                }
            }

            SettingsGroup("ORDER AND SHAPE")
            SettingsParagraph("The feed runs newest first and groups by day. Neither of those is a setting yet, so neither is offered as one here.")
            SettingsParagraph("Every post carries the sender\u{2019}s own words in sans and ours in mono. That is not a preference either \u{2014} it is how you tell them apart.")
        }
        .sheet(isPresented: $filtering) {
            MailboxFilterSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
    }

    private var countLabel: String {
        let showing = store.mailboxes.count(where: \.includeInUnifiedFeed)
        return showing == store.mailboxes.count
            ? "ALL \(store.mailboxes.count)"
            : "\(showing) OF \(store.mailboxes.count)"
    }
}

// MARK: - Filter sheet

/// `03 · Filter sheet`.
///
/// Full-bleed rows inside a sheet with no horizontal padding of its own, and a
/// primary button whose label counts the live selection.
///
/// Deselecting everything is refused rather than accepted: an empty filter set
/// falls through to "show everything" downstream, so a button that said "Show
/// these 0" would do the opposite of what it promised.
struct MailboxFilterSheet: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: Set<String> = []
    @State private var query = ""

    var body: some View {
        SheetChrome {
            VStack(spacing: 0) {
                HStack(spacing: Space.md) {
                    Text("Show which mailboxes?")
                        .typeStyle(Style.navTitle)
                        .foregroundStyle(Ink.primary)
                    Spacer(minLength: Space.md)
                    Button("ALL") {
                        withAnimation(Move.crisp) {
                            chosen = Set(store.mailboxes.map(\.id))
                        }
                    }
                    .typeStyle(Style.monoAction)
                    .foregroundStyle(Ink.primary)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, Space.sm)

                SearchField(text: $query, placeholder: "Filter")
                    .padding(.horizontal, Metric.gutter)
                    .padding(.bottom, Space.md)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { mailbox in
                            ListRow(
                                title: mailbox.address,
                                subtitle: mailbox.stateLabel,
                                action: { toggle(mailbox.id) },
                                leading: { MailboxTag(mailbox.tag, size: Metric.avatarRow) },
                                trailing: {
                                    InkCheckbox(isOn: chosen.contains(mailbox.id))
                                }
                            )
                            .accessibilityAddTraits(.isToggle)
                            .accessibilityValue(chosen.contains(mailbox.id) ? "Shown" : "Hidden")
                            Rule()
                        }

                        if filtered.isEmpty {
                            Text("No mailbox matches \u{201C}\(query)\u{201D}.")
                                .typeStyle(Style.bodySmall)
                                .foregroundStyle(Ink.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Metric.gutter)
                                .padding(.vertical, Space.xl)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                PrimaryButton(label: buttonLabel, enabled: !chosen.isEmpty) {
                    for mailbox in store.mailboxes {
                        store.setIncluded(mailbox.id, chosen.contains(mailbox.id))
                    }
                    dismiss()
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xl)
            }
        }
        // The sheet's own ground is cleared so the 24pt top corners are ours,
        // which means the chrome has to fill the detent itself or the screen
        // behind shows through. The hairline underneath carries the ground on
        // down through the home-indicator strip — the sheet has no bottom
        // radius, so it must not stop short of the edge either.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .bottom) {
            Ink.surface.frame(height: 1).ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            chosen = Set(store.mailboxes.filter(\.includeInUnifiedFeed).map(\.id))
        }
    }

    private var filtered: [Mailbox] {
        guard !query.isEmpty else { return store.mailboxes }
        return store.mailboxes.filter {
            $0.address.localizedCaseInsensitiveContains(query)
                || $0.tag.localizedCaseInsensitiveContains(query)
        }
    }

    private var buttonLabel: String {
        if chosen.isEmpty { return "Pick at least one" }
        if chosen.count == store.mailboxes.count { return "Show all \(chosen.count)" }
        return "Show these \(chosen.count)"
    }

    private func toggle(_ id: String) {
        withAnimation(Move.crisp) {
            if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
        }
    }
}

#Preview {
    NavigationStack { SettingsFeedView() }
        .environment(FeedStore(sample: true))
}
