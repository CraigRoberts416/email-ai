import SwiftUI

/// The connect flow, built to `Flows · Onboarding & Accounts / 01–05`.
///
/// The one full-screen block in the product. Everything else degrades quietly;
/// a missing mailbox is the single thing the app cannot work around.
///
/// The primer earns its place: this app asks for `https://mail.google.com/`,
/// which is read, send and delete over someone's entire mail. Google's own
/// consent screen states that in its language, once, in a list. Saying it
/// first, in ours, is the difference between disclosure and consent.
struct OnboardingFlow: View {
    let auth: AuthService

    enum Step: Equatable {
        case premise
        case provider
        case primer(Provider)
        case connecting
        case cancelled
    }

    @State private var step: Step = .premise

    var body: some View {
        Group {
            switch step {
            case .premise: premise
            case .provider: providers
            case .primer(let provider): primer(provider)
            case .connecting: connecting
            case .cancelled: cancelled
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.surface)
        .animation(Move.crossfade, value: step)
    }

    // MARK: 01 · Premise

    private var premise: some View {
        hero {
            Text("EXAMPLE")
                .typeStyle(Style.kickerSmall)
                .foregroundStyle(Ink.tertiary)

            ExamplePost()

            Text("You already know what most of your email says. This just tells you first.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.xl)

            PrimaryButton(label: "Connect a mailbox") { step = .provider }

            Text("No account to make. Your mailbox is the account.")
                .typeStyle(Style.monoCaption)
                .foregroundStyle(Ink.tertiary)
        }
    }

    // MARK: 02 · Provider

    private var providers: some View {
        hero {
            Text("Where does your mail live?")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                Rule()
                ForEach(Provider.allCases) { provider in
                    Button {
                        guard provider.isSupported else { return }
                        step = .primer(provider)
                    } label: {
                        HStack(spacing: Space.lg) {
                            ProviderMark(provider: provider)
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(provider.name)
                                    .typeStyle(Style.sender)
                                    .foregroundStyle(provider.isSupported ? Ink.primary : Ink.tertiary)
                                Text(provider.meta)
                                    .typeStyle(Style.monoCaption)
                                    .foregroundStyle(Ink.tertiary)
                            }
                            Spacer(minLength: Space.md)
                            if provider.isSupported {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Ink.tertiary)
                            }
                        }
                        .padding(.vertical, 18)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!provider.isSupported)
                    Rule()
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: 03 · Permission primer

    private func primer(_ provider: Provider) -> some View {
        hero {
            Text("Google is about to ask for a lot. Here is exactly what for.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.lg) {
                scope("READ YOUR MAIL", "There is no card without the message behind it.")
                scope("SEND AS YOU", "Only when you tap send. Never on its own, never to another AI.")
                scope("CHANGE LABELS", "So archiving here archives in Gmail too.")
                scope("CONTACT PHOTOS", "Read-only access to saved contacts and Other Contacts lets this phone match real photos by email address. Your address book is not sent to our server.")
            }

            Text("Contact photos are optional. We never ask for your calendar or your password.")
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.xl)

            PrimaryButton(label: "Continue to \(provider.name)") {
                step = .connecting
                Task {
                    await auth.connect()
                    // `connect` returns nil when the user backed out of the
                    // system sheet, which is a choice rather than a failure.
                    if !auth.isAuthenticated { step = .cancelled }
                }
            }

            NavigationLink { StorageView() } label: {
                Text("What we store")
                    .typeStyle(Style.sender)
                    .foregroundStyle(Ink.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.lg)
                    .overlay(Capsule().strokeBorder(Ink.primary, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    /// Each scope gets a 2pt rule rather than a bullet. A list of permissions
    /// with bullets reads as marketing; a list with rules reads as a receipt.
    private func scope(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .typeStyle(Style.kickerSmall)
                .foregroundStyle(Ink.primary)
            Text(detail)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, Space.md)
        .overlay(alignment: .leading) {
            Rectangle().fill(Ink.border).frame(width: 2)
        }
    }

    // MARK: 04 · Connecting

    /// No spinner. The design withholds one deliberately: the wait is a few
    /// seconds of Google's own sheet, and a spinner would be the app claiming
    /// to be busy while it waits on somebody else.
    private var connecting: some View {
        VStack(spacing: Space.lg) {
            Text("Connecting \(Provider.google.name)")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
            if let address = auth.accounts.first?.id {
                Text(address.uppercased())
                    .typeStyle(Style.kickerSmall)
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Space.xxl)
    }

    // MARK: 05 · Cancelled

    private var cancelled: some View {
        hero {
            Text("You didn\u{2019}t finish connecting.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(auth.lastError ?? "Nothing was shared and nothing was stored. You can pick up where you left off, or use a different mailbox.")
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.xl)

            PrimaryButton(label: "Try again") {
                step = .connecting
                Task {
                    await auth.connect()
                    if !auth.isAuthenticated { step = .cancelled }
                }
            }
            GhostButton(label: "Choose a different provider") { step = .provider }
        }
    }

    // MARK: Shell

    /// 80pt of air above, 24 either side. Hero screens breathe wider than
    /// lists do, and the top pad is what stops them reading as a form.
    private func hero<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            content()
        }
        .padding(.top, Metric.heroTopPad)
        .padding(.horizontal, Metric.gutterWide)
        .padding(.bottom, Space.xxl)
    }
}

// MARK: - Providers

enum Provider: String, CaseIterable, Identifiable {
    case google, outlook, yahoo

    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Gmail"
        case .outlook: return "Outlook"
        case .yahoo: return "Yahoo Mail"
        }
    }

    /// Only Gmail works. The other two are shown because the design shows
    /// them, and marked because a picker whose options do nothing is a worse
    /// lie than a shorter list.
    var isSupported: Bool { self == .google }

    var meta: String {
        switch self {
        case .google: return "gmail.com · google workspace"
        case .outlook: return "outlook.com · not yet"
        case .yahoo: return "yahoo.com · not yet"
        }
    }

    var monogram: String {
        switch self {
        case .google: return "G"
        case .outlook: return "O"
        case .yahoo: return "Y"
        }
    }
}

private struct ProviderMark: View {
    let provider: Provider

    var body: some View {
        Text(provider.monogram)
            .typeStyle(Style.sender)
            .foregroundStyle(provider.isSupported ? Ink.primary : Ink.tertiary)
            .frame(width: Metric.avatarList, height: Metric.avatarList)
            .background(Circle().fill(Ink.surface))
            .overlay(Circle().strokeBorder(Ink.border, lineWidth: 1))
    }
}

// MARK: - The example

/// The one place in the product a post is drawn inside a container. It is a
/// specimen being shown to someone who has never seen one, not a post in a
/// feed — and the border is what says so.
private struct ExamplePost: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.md) {
                Text("D")
                    .typeStyle(Style.sender)
                    .foregroundStyle(Ink.primary)
                    .frame(width: Metric.avatar, height: Metric.avatar)
                    .background(
                        RoundedRectangle(cornerRadius: Metric.avatar * 0.25, style: .continuous)
                            .fill(Ink.surfaceTertiary)
                    )
                Text("Delta Air Lines")
                    .typeStyle(Style.sender)
                    .foregroundStyle(Ink.primary)
                Spacer(minLength: 0)
                Text("2h")
                    .typeStyle(Style.meta)
                    .foregroundStyle(Ink.tertiary)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                Text(Kicker.fyi.rawValue)
                    .typeStyle(Style.kicker)
                    .foregroundStyle(Ink.primary)
                Text("\u{201C}Departure moved to 8:15 AM\u{201D}")
                    .typeStyle(Style.display)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("DL204 now leaves 55 minutes earlier than booked. Check in before you head out.")
                .typeStyle(Style.ai)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Space.md)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Ink.border).frame(width: 1)
                }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                .strokeBorder(Ink.border, lineWidth: 1)
        )
    }
}
