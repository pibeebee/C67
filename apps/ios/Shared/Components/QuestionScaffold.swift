import SwiftUI
import UIKit

/// Screen layout shared by the trip preference questions.
///
/// Shows a `QuestionTitle`, the question's content, an optional bottom action and a native
/// Skip toolbar button. Push it inside a `NavigationStack`; the system back button provides the
/// leading control.
struct QuestionScaffold<Content: View, Footer: View>: View {
    private let title: Text
    private let contentSpacing: CGFloat
    private let skip: (() -> Void)?
    private let content: Content
    private let footer: Footer

    init(
        title: Text,
        contentSpacing: CGFloat = 64,
        skip: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.contentSpacing = contentSpacing
        self.skip = skip
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                QuestionTitle(title)
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .bottomActionBar(isVisible: Footer.self != EmptyView.self) {
            footer
        }
        .background(AppColor.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let skip {
                    Button("Skip", action: skip)
                }
            }
        }
        .tint(AppColor.accent)
    }
}

extension QuestionScaffold where Footer == EmptyView {
    init(
        title: Text,
        contentSpacing: CGFloat = 64,
        skip: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, contentSpacing: contentSpacing, skip: skip, content: content) {
            EmptyView()
        }
    }
}

extension View {
    /// Pins trip actions to the safe area with consistent margins and a centered width.
    func bottomActionBar<Bar: View>(isVisible: Bool = true, background: Color? = nil, @ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(BottomActionBar(bar: bar(), isVisible: isVisible, background: background))
    }
}

private struct BottomActionBar<Bar: View>: ViewModifier {
    let bar: Bar
    let isVisible: Bool
    let background: Color?

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .safeAreaBar(edge: .bottom, spacing: 0) { positionedBar }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) { positionedBar }
        }
    }

    @ViewBuilder private var positionedBar: some View {
        if isVisible {
            bar
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .background { if let background { background } }
        }
    }
}

/// The system `UISearchBar` for search fields that live in content rather than under a navigation
/// bar (where `.searchable` would place them): native field, clear button and Cancel while typing.
struct NativeSearchBar: UIViewRepresentable {
    @Binding var text: String
    let prompt: String
    let accessibilityIdentifier: String
    /// Mirrors the field's first-responder state; setting it to true focuses the field.
    var isFocused: Binding<Bool>?
    var onSubmit: () -> Void = {}

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = prompt
        bar.autocorrectionType = .no
        bar.returnKeyType = .search
        bar.delegate = context.coordinator
        bar.searchTextField.accessibilityIdentifier = accessibilityIdentifier
        bar.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        if bar.text != text { bar.text = text }
        guard let isFocused else { return }
        if isFocused.wrappedValue, !bar.isFirstResponder {
            DispatchQueue.main.async { bar.becomeFirstResponder() }
        } else if !isFocused.wrappedValue, bar.isFirstResponder {
            DispatchQueue.main.async { bar.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativeSearchBar

        init(parent: NativeSearchBar) { self.parent = parent }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { parent.text = searchText }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(true, animated: true)
            if parent.isFocused?.wrappedValue == false { parent.isFocused?.wrappedValue = true }
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(false, animated: true)
            if parent.isFocused?.wrappedValue == true { parent.isFocused?.wrappedValue = false }
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.onSubmit()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.text = ""
            searchBar.text = ""
            searchBar.resignFirstResponder()
        }
    }
}
