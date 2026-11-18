import SwiftUI

struct RecoveryNotice: View {
    struct Action {
        let title: LocalizedStringKey
        let perform: () -> Void
    }

    let title: LocalizedStringKey
    let message: String
    var icon = "exclamationmark.circle"
    var primary: Action?
    var secondary: Action?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(message).font(.footnote).foregroundStyle(.secondary)
            if let primary { Button(primary.title, action: primary.perform).buttonStyle(.borderless) }
            if let secondary { Button(secondary.title, action: secondary.perform).buttonStyle(.borderless) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColor.surface, in: .rect(cornerRadius: 16))
    }
}
