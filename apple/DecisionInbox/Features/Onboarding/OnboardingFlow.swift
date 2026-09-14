import SwiftUI

/// The one full-screen block in the whole product. Everything else degrades
/// quietly; a missing mailbox is the single thing the app cannot work around.
struct OnboardingFlow: View {
    let auth: AuthService

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Spacer()
            Text("Your inbox,\nalready read.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
            Text("Decision Inbox reads every email as it lands and tells you what it wants \u{2014} before you open it.")
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()

            if let error = auth.lastError {
                Text(error)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.surfaceTertiary)
            }

            Button {
                Task { await auth.connect() }
            } label: {
                Text(auth.isConnecting ? "Connecting\u{2026}" : "Connect a mailbox")
                    .typeStyle(Style.sender)
                    .foregroundStyle(Ink.onInverse)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.lg)
                    .background(Ink.inverse, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(auth.isConnecting)

            Text("NO ACCOUNT TO MAKE. YOUR MAILBOX IS THE ACCOUNT.")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.surface)
    }
}
