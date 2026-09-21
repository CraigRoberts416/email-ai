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
    @State private var includeGooglePhotos = false
    @State private var longWait = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            backButton(to: .premise)
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
            backButton(to: .provider)
            Text("Google is about to ask for a lot. Here is exactly what for.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.lg) {
                scope("READ YOUR MAIL", "There is no card without the message behind it.")
                scope("SEND AS YOU", "When you choose to send a message or submit an unsubscribe request. The app does not send independent messages.")
                scope("MANAGE YOUR MAIL", "Google’s mailbox permission includes reading, sending, changing labels and permanently deleting mail. The app uses it to show your mail and carry out actions you choose; it does not independently delete messages.")

            }

            Toggle("Also connect Google contact photos", isOn: $includeGooglePhotos)
                .tint(Ink.primary)
            Text("Optional and off by default. This adds read-only access to Google contacts and Other Contacts for exact-address photo matching on this phone. You can connect photos later in Privacy. We never ask for your calendar or your password.")
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.xl)

            PrimaryButton(label: "Continue to \(provider.name)") {
                step = .connecting
                Task {
                    await auth.connect(includeGooglePhotos: includeGooglePhotos)
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
        hero {
            Text(auth.connectionStage == .waitingForGoogle ? "Continue in Google" : "Finishing the connection")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(auth.connectionStage == .waitingForGoogle
                 ? "Choose the mailbox and review Google's permissions in the sign-in window."
                 : "Checking which mailbox you connected and saving its credentials on this device.")
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if longWait {
                Text("Still waiting. If Google is no longer open or your connection has stalled, cancel and try again. No completion has been confirmed.")
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GhostButton(label: "Cancel connection") { auth.cancelConnection() }
                .keyboardShortcut(.cancelAction)
        }
        .task {
            longWait = false
            do { try await Task.sleep(for: .seconds(10)); longWait = true } catch {}
        }
    }

    // MARK: 05 · Cancelled

    private var cancelled: some View {
        hero {
            PaperIllustration(art: .reading, phase: 3).frame(width: 150, height: 92)
            Text(auth.lastError == nil ? "Connection cancelled." : "Connection could not finish.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(auth.lastError ?? "This mailbox was not added. You can try again when you are ready. Any permissions already granted can be managed in your Google Account.")
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.xl)

            PrimaryButton(label: "Try again") {
                step = .connecting
                Task {
                    await auth.connect(includeGooglePhotos: includeGooglePhotos)
                    if !auth.isAuthenticated { step = .cancelled }
                }
            }
            GhostButton(label: "Choose a different provider") { step = .provider }
        }
    }

    // MARK: Shell

    /// 80pt of air above, 24 either side. Hero screens breathe wider than
    /// lists do, and the top pad is what stops them reading as a form.
    private func backButton(to destination: Step) -> some View {
        Button { step = destination } label: {
            Label("Back", systemImage: "chevron.left")
                .typeStyle(Style.bodyMedium)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func hero<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) { content() }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.top, Space.xxl)
                .padding(.horizontal, Metric.gutterWide)
                .padding(.bottom, Space.xxl)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
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
    @State private var showingMeaning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("SYNTHETIC EXAMPLE · NOT YOUR MAIL")
                .typeStyle(Style.monoMicro)
                .foregroundStyle(Ink.tertiary)
            PaperIllustration(art: .reading, phase: showingMeaning ? 2 : 0)
                .frame(maxWidth: .infinity).frame(height: typeSize.isAccessibilitySize ? 88 : 120)
            Text("Delta Air Lines")
                .typeStyle(Style.sender)
                .foregroundStyle(Ink.primary)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.sm) {
                    specimenButton("Original email", meaning: false)
                    specimenButton("What it means", meaning: true)
                }
            } else {
                HStack(spacing: Space.md) {
                    specimenButton("Original email", meaning: false)
                    specimenButton("What it means", meaning: true)
                }
            }
            Group {
                if showingMeaning {
                    VStack(alignment: .leading, spacing: Space.md) {
                        Text("FROM THE EMAIL")
                            .typeStyle(Style.kickerSmall)
                        Text("“Departure moved to 8:15 AM”")
                            .typeStyle(Style.bodyMedium)
                        Rule()
                        Text("OUR INTERPRETATION")
                            .typeStyle(Style.kickerSmall)
                        Text("Your flight leaves 55 minutes earlier. Leave time to check in before heading out.")
                            .typeStyle(Style.ai)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Space.md) {
                        Text("Schedule update for DL204")
                            .typeStyle(Style.bodyMedium)
                        Text("Departure moved to 8:15 AM. Your original departure time was 9:10 AM. Please check in before arriving at the airport.")
                            .typeStyle(Style.body)
                    }
                }
            }
            .foregroundStyle(Ink.primary)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
            Text("The quote is the sender's wording. The interpretation can be wrong; the original stays available.")
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Corner.md).strokeBorder(Ink.border, lineWidth: 1))
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-sampleMeaning") { showingMeaning = true }
        }
        #endif
    }

    private func specimenButton(_ title: String, meaning: Bool) -> some View {
        Button {
            withAnimation(Move.resolved(Move.layout, reduceMotion)) { showingMeaning = meaning }
        } label: {
            Text(title)
                .typeStyle(Style.bodySmall)
                .foregroundStyle(showingMeaning == meaning ? Ink.onInverse : Ink.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.md)
                .padding(.vertical, typeSize.isAccessibilitySize ? Space.sm : 0)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                .frame(minHeight: 44)
                .background {
                    if typeSize.isAccessibilitySize {
                        RoundedRectangle(cornerRadius: Corner.md)
                            .fill(showingMeaning == meaning ? Ink.inverse : Ink.surfaceTertiary)
                    } else {
                        Capsule().fill(showingMeaning == meaning ? Ink.inverse : Ink.surfaceTertiary)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(showingMeaning == meaning ? .isSelected : [])
    }
}
