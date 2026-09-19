import SwiftUI

/// The system owns back-control placement and material. On iOS 26 this is
/// adaptive Liquid Glass; earlier systems use their native toolbar treatment.
/// A supplied action also works at the root of a presented NavigationStack.
private struct BackNavigation: ViewModifier {
    let title: String?
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left", action: action)
                        .labelStyle(.iconOnly)
                        // The app's fixed black accent must not pin this
                        // symbol to black over a dark hero. A hierarchical
                        // style keeps the native glass foreground adaptive.
                        .tint(HierarchicalShapeStyle.primary)
                }
                if let title {
                    ToolbarItem(placement: .principal) {
                        Text(title).typeStyle(Style.navTitle).lineLimit(1)
                    }
                }
            }
    }
}

extension View {
    func backNavigation(title: String? = nil, action: @escaping () -> Void) -> some View {
        modifier(BackNavigation(title: title, action: action))
    }
}
