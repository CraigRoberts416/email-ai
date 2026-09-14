import SwiftUI

/// Empty and error deliberately do not share a component. Reusing one shell
/// teaches people that "nothing here" and "something broke" look alike, and
/// they stop reading both.
///
/// No illustration: scale is the illustration.
struct EmptyStateView: View {
    let headline: String
    let detail: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(headline)
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .typeStyle(Style.monoSmall)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .typeStyle(Style.sender)
                        .foregroundStyle(Ink.primary)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.md)
                        .overlay(Capsule().strokeBorder(Ink.primary, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.gutter)
        .padding(.top, 140)
    }
}
