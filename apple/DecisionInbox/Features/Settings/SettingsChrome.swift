import SwiftUI
import UIKit

// The furniture every settings screen is assembled from.
//
// Nothing here is a system control. `List`, `Form`, `Toggle` and
// `.navigationTitle` all bring back the tint, the inset rounded row and the
// blurred bar this design spent its argument removing — so the screens are
// built out of `Controls.swift` instead: `NavBar`, `SectionHeader`, `ListRow`,
// `RowArrow`, `RowValue`, `InkToggle`, `InkCheckbox`, `PrimaryButton`,
// `SearchField`, `TagPill`, `SheetChrome`.
//
// One typographic rule runs through all of it, and it is the one the content
// audit found broken: **uppercase mono is a label or a count; a sentence is set
// in sentence case.** Row sub-labels (`SYNCED 14:02`, `3 OF 12 MAILBOXES`) are
// furniture and stay mono. Anything with a verb and a full stop — especially
// the warning under a destructive action — is a sentence, and gets read.

// MARK: - Screen shell

/// Nav bar pinned above a scroller, on the product's own ground. The system
/// bar is hidden rather than styled: there is no configuration of it that
/// produces this.
struct SettingsScreen<Content: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: title, onBack: onBack)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
                // The tab bar floats over content, so a settings screen has to
                // clear it itself or its last row sits underneath.
                .safeAreaPadding(.bottom, Space.xxxl + Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(Ink.surface)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Group header

/// A group header, with the explanatory caption the Figma puts under several
/// of them. The label is a label, so it is mono and upper-cased; the caption is
/// a sentence, so it is not.
struct SettingsGroup: View {
    let title: String
    var caption: String?
    var trailing: String?
    var onTrailing: (() -> Void)?

    init(
        _ title: String,
        caption: String? = nil,
        trailing: String? = nil,
        onTrailing: (() -> Void)? = nil
    ) {
        self.title = title
        self.caption = caption
        self.trailing = trailing
        self.onTrailing = onTrailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title, trailing: trailing, onTrailing: onTrailing)
            if let caption {
                Text(caption)
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.bottom, Space.md)
            }
        }
        // Combining is right for a plain header — label and caption are one
        // announcement. It is wrong the moment the header carries an action,
        // because combining folds the button in and VoiceOver can no longer
        // reach it.
        .accessibilityElement(children: onTrailing == nil ? .combine : .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Rows

/// A toggle row. The whole row is the target and the switch is the readout —
/// a 44 × 26 control is under the 44pt minimum in one dimension, and hunting
/// for it is not a skill anyone should need.
struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        ListRow(
            title: title,
            subtitle: subtitle,
            action: { withAnimation(Move.crisp) { isOn.toggle() } },
            trailing: {
                InkToggle(isOn: $isOn)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        )
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A row that pushes somewhere, with an optional value beside the arrow.
struct SettingsLink: View {
    let title: String
    var subtitle: String?
    var value: String?
    let action: () -> Void

    var body: some View {
        ListRow(
            title: title,
            subtitle: subtitle,
            action: action,
            trailing: {
                HStack(spacing: Space.sm) {
                    if let value { RowValue(value) }
                    RowArrow()
                }
            }
        )
        .accessibilityHint(value.map { "Currently \($0.lowercased())" } ?? "")
    }
}

/// A row stating a fact the app knows rather than a setting the user picks.
/// No arrow and no control — if there were nothing to read it would not be here.
struct SettingsFact: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Space.md) {
            Text(title)
                .typeStyle(Style.bodyMedium)
                .foregroundStyle(Ink.primary)
            Spacer(minLength: Space.sm)
            RowValue(value)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .combine)
    }
}

/// A row that carries a consequence rather than a value.
///
/// The sentence underneath is set in sentence case, in body type, in ink — not
/// in 10pt upper-case mono. It is the single most important line on the screen
/// it appears on, and it was previously in the least readable treatment the
/// product owns. Destructive rows step the title to medium and confirm on a
/// second tap; there is no red anywhere, because weight is the signal.
struct ConsequenceRow: View {
    let title: String
    let sentence: String
    var confirmTitle: String?
    var destructive = false
    let action: () -> Void

    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                guard confirmTitle != nil, !confirming else {
                    confirming = false
                    action()
                    return
                }
                withAnimation(Move.crisp) { confirming = true }
            } label: {
                Text(confirming ? (confirmTitle ?? title) : title)
                    .typeStyle(destructive ? Style.sender : Style.bodyMedium)
                    .foregroundStyle(confirming ? Ink.onInverse : Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, Space.lg)
                    // Asymmetric on purpose: the sentence belongs to the
                    // control, and 24pt of air between them makes it read as
                    // unrelated fine print.
                    .padding(.bottom, 10)
                    .background(confirming ? Ink.inverse : Ink.surface)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The consequence travels with the control rather than sitting in
            // a separate element a VoiceOver user might never reach — and the
            // button stays a button, which combining the stack would undo.
            .accessibilityHint(confirming ? "Confirms. \(sentence)" : sentence)

            Text(sentence)
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, Space.lg)
        }
    }
}

// MARK: - Prose

/// A paragraph with no row around it, for the things that are true but are not
/// settings. The Figma gives it body type in ink — it is meant to be read once,
/// properly, not skimmed as furniture.
struct SettingsParagraph: View {
    let text: String
    var emphasised = true

    init(_ text: String, emphasised: Bool = true) {
        self.text = text
        self.emphasised = emphasised
    }

    var body: some View {
        Text(text)
            .typeStyle(emphasised ? Style.body : Style.bodySmall)
            .foregroundStyle(emphasised ? Ink.primary : Ink.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metric.gutter)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.lg)
    }
}

// MARK: - Share

/// Handing a file to the user. There is no design-system component for this and
/// inventing one would mean reimplementing the share sheet, so it is the system
/// one — the only place in the product that is true.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
