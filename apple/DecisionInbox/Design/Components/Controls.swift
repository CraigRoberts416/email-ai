import SwiftUI

// The shared furniture of every list and sheet screen.
//
// None of these are system controls, and that is the point. UIKit's switch is
// 51×26 and green; iOS list rows inset and round themselves; a sheet arrives
// with a shadow. Every one of those defaults would put back the colour and
// the containers this design spent its whole argument removing.

// MARK: - Press feedback
//
// Input is acknowledged on touch-down everywhere, and it is acknowledged
// visually. No press-down in this product fires a haptic: presses are the most
// frequent event there is, and spending the tactile budget on them is what
// trains people to stop noticing the cues that carry real information. Cues
// fire at commit — see Haptics.swift.
//
// These live here rather than in Tokens.swift because this is the file that
// already owns the product's buttons.

/// A post acknowledges a press with a **fill change and no scale**.
///
/// The reason is specific rather than a preference: a full-width decontained
/// post that scales pulls its edge-to-edge hairlines out of alignment with its
/// neighbours' and momentarily reads as a card — undoing the single decision
/// the whole feed is built on.
///
/// The fill is reported to the row rather than drawn on the label, because a
/// post's tappable region ends above its action row while its ground does not:
/// the action row's own buttons cannot live inside a button's label and still
/// receive taps.
struct PostPressStyle: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                withAnimation(isPressed ? Move.pressIn : Move.pressOut) {
                    pressed = isPressed
                }
            }
    }
}

/// Small controls — anything that is not a whole post. A scale step is legible
/// on a 44pt target in a way a fill change is not, and nothing structural is
/// pulled out of alignment by it.
struct TapStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Reduce Motion drops the scale and keeps the opacity: the
            // acknowledgement survives, the travel does not.
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.94)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(configuration.isPressed ? Move.pressIn : Move.pressOut,
                       value: configuration.isPressed)
    }
}

// MARK: - Toggle

/// 44×26 with a 20pt knob on a 3pt inset. Black when on, `#EEEEEE` when off.
/// The system switch is a different size and a different colour, so it cannot
/// stand in here.
struct InkToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Ink.primary : Ink.border)
            // #EEEEEE on white is 1.16:1, and the white knob on it is another
            // 1.16:1 — an off switch with no edge is invisible, which matters
            // most on the privacy rows where off is the consequential state.
            .overlay(Capsule().strokeBorder(isOn ? .clear : Ink.tertiary, lineWidth: 1))
            .frame(width: 44, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Ink.surface)
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(Move.crisp) { isOn.toggle() }
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Checkbox

struct InkCheckbox: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Corner.checkbox, style: .continuous)
            .fill(isOn ? Ink.primary : .clear)
            .frame(width: 22, height: 22)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.onInverse)
                } else {
                    RoundedRectangle(cornerRadius: Corner.checkbox, style: .continuous)
                        .strokeBorder(Ink.border, lineWidth: 1)
                }
            }
    }
}

// MARK: - Buttons

/// The filled button. There is at most one per screen, and it is the thing
/// the screen exists to do.
struct PrimaryButton: View {
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .typeStyle(Style.sender)
                .foregroundStyle(enabled ? Ink.onInverse : Ink.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.lg)
                .background(enabled ? Ink.inverse : Ink.border, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// The same box with the fill taken out. A black hairline, never grey — a grey
/// outline reads as disabled.
struct GhostButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .typeStyle(Style.sender)
                .foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.lg)
                .overlay(Capsule().strokeBorder(Ink.primary, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Nav bar

/// Root-screen heading. Detail screens use the shared system back toolbar.
struct NavBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.md) {
            Text(title)
                .typeStyle(Style.navTitle)
                .foregroundStyle(Ink.primary)
            Spacer(minLength: Space.md)
            trailing
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, Space.xl - 4)
        .padding(.bottom, Space.md)
    }
}

extension NavBar where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var trailing: String?
    var onTrailing: (() -> Void)?

    init(_ title: String, trailing: String? = nil, onTrailing: (() -> Void)? = nil) {
        self.title = title
        self.trailing = trailing
        self.onTrailing = onTrailing
    }

    var body: some View {
        HStack {
            Text(title)
                .typeStyle(Style.sectionHeader)
                .foregroundStyle(Ink.tertiary)
            Spacer(minLength: Space.md)
            if let trailing {
                Button(trailing) { onTrailing?() }
                    .typeStyle(Style.monoAction)
                    .foregroundStyle(Ink.primary)
                    .buttonStyle(.plain)
                    .disabled(onTrailing == nil)
            }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, Space.xl - 2)
        .padding(.bottom, Space.sm)
    }
}

// MARK: - List row

/// One row shape for every list in the product. The file carries two — a
/// roomier onboarding pass and a denser mailboxes pass — and shipping both is
/// the kind of drift a reader feels but cannot name, so this is the dense one
/// applied everywhere.
struct ListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var muted = false
    var action: (() -> Void)?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: Space.md) {
                leading
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title)
                        .typeStyle(Style.bodyMedium)
                        .foregroundStyle(muted ? Ink.tertiary : Ink.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle)
                            .typeStyle(Style.monoMicro)
                            .foregroundStyle(Ink.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.sm)
                trailing
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, Space.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

extension ListRow where Leading == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        muted: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title: title, subtitle: subtitle, muted: muted, action: action,
                  leading: { EmptyView() }, trailing: trailing)
    }
}

extension ListRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        muted: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder leading: () -> Leading
    ) {
        self.init(title: title, subtitle: subtitle, muted: muted, action: action,
                  leading: leading, trailing: { EmptyView() })
    }
}

/// The disclosure arrow. `arrow.right`, not `chevron.right` — the file is
/// consistent about it and the two read differently at 13pt.
struct RowArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 13))
            .foregroundStyle(Ink.tertiary)
    }
}

/// A settings value shown inline — GMAIL, 30 DAYS, NEWEST.
struct RowValue: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .typeStyle(Style.monoSmall)
            .foregroundStyle(Ink.tertiary)
    }
}

// MARK: - Search field

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Ink.tertiary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Ink.tertiary))
                .typeStyle(Style.bodyMedium)
                .foregroundStyle(Ink.primary)
                .tint(Ink.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Ink.surfaceTertiary, in: Capsule())
    }
}

// MARK: - Account tag

/// Two to four characters, on a tertiary pill. Never a circle — a circle is a
/// person, and a mailbox is a place.
struct TagPill: View {
    let tag: String
    init(_ tag: String) { self.tag = tag }

    var body: some View {
        Text(tag)
            .typeStyle(Style.chip)
            .foregroundStyle(Ink.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Corner.chip, style: .continuous)
                    .fill(Ink.surfaceTertiary)
            )
    }
}

// MARK: - Sheet chrome

/// Top corners only, no shadow. The file defines none, and an invented one
/// would be the only soft edge in the product.
struct SheetChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Ink.border)
                .frame(width: 40, height: 4)
                .padding(.top, Space.md)
                .padding(.bottom, Space.lg)
            content
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: Corner.xl, topTrailingRadius: Corner.xl, style: .continuous
            )
            .fill(Ink.surface)
        )
    }
}
